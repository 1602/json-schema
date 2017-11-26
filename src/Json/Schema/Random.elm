module Json.Schema.Random exposing (value, valueAt, GeneratorSettings, defaultSettings)

{-|
Generate random values based on JSON Schema.

Experimental module.

# Generator

@docs value, valueAt

# Settings

@docs GeneratorSettings, defaultSettings

-}

import Json.Schema.Definitions
    exposing
        ( Schema(ObjectSchema, BooleanSchema)
        , Schemata(Schemata)
        , Type(SingleType)
        , SingleType(IntegerType, NumberType, StringType, BooleanType, NullType, ArrayType, ObjectType)
        , Items(ItemDefinition, ArrayOfItems, NoItems)
        )
import Json.Encode as Encode exposing (Value)
import Random exposing (Generator, Seed)
import Char
import Util exposing (getAt, uncons)
import Json.Schema.Helpers exposing (collectIds)
import Ref exposing (defaultPool)
import Dict


{-|
Customize generator behaviour using following parameters:
- optionalPropertyProbability : float from 0 to 1, which affects used while generating object with optional property, default 0.5
- degradationMultiplier : used in nested objects to affect probability of optional property appearance (must have for recursive objects), default 0.2
- defaultListLengthLimit : how many items in array to generate when limit is not set by a schema, default 100
- defaultStringLengthLimit : how many characters in random string to generate when limit is not set by a schema, default 100
-}
type alias GeneratorSettings =
    { optionalPropertyProbability : Float
    , degradationMultiplier : Float
    , defaultListLengthLimit : Int
    , defaultStringLengthLimit : Int
    }


{-|
Defaults for GeneratorSettings
-}
defaultSettings : GeneratorSettings
defaultSettings =
    GeneratorSettings
        -- optionalPropertyProbability
        0.5
        -- degradationMultiplier
        0.2
        -- defaultListLengthLimit
        100
        -- defaultStringLengthLimit
        100


randomString : Int -> Int -> Maybe String -> Generator String
randomString minLength maxLength format =
    case format of
        Just "url" ->
            Random.bool
                |> Random.map
                    (\x ->
                        if x then
                            "http://example.com/"
                        else
                            "https://github.com"
                    )

        Just "uri" ->
            Random.bool
                |> Random.map
                    (\x ->
                        if x then
                            "http://example.com/"
                        else
                            "https://github.com"
                    )

        Just "email" ->
            Random.int 1000 9999
                |> Random.map
                    (\x -> "rcp" ++ (toString x) ++ "@receipt.to")

        Just "host-name" ->
            Random.bool
                |> Random.map
                    (\x ->
                        if x then
                            "example.com"
                        else
                            "github.com"
                    )

        Just "date-time" ->
            Random.bool
                |> Random.map (\_ -> "2018-01-01T09:00:00Z")

        Just "time" ->
            Random.bool
                |> Random.map (\_ -> "09:00:00")

        Just "date" ->
            Random.bool
                |> Random.map (\_ -> "2018-01-01")

        _ ->
            Random.int minLength maxLength
                |> Random.andThen (flip Random.list lowercaseLetter)
                |> Random.map (String.fromList)


lowercaseLetter : Generator Char
lowercaseLetter =
    Random.map (\n -> Char.fromCode (n + 97)) (Random.int 0 25)


randomItemFromList : ( a, List a ) -> Generator a
randomItemFromList ( head, tail ) =
    let
        list =
            head :: tail
    in
        list
            |> List.length
            |> (+) -1
            |> Random.int 0
            |> Random.map (flip getAt list >> (Maybe.withDefault head))


nullGenerator : Generator Value
nullGenerator =
    Random.bool |> Random.map (\_ -> Encode.null)


upgradeSettings : GeneratorSettings -> GeneratorSettings
upgradeSettings settings =
    { settings
        | optionalPropertyProbability =
            settings.optionalPropertyProbability * settings.degradationMultiplier
    }


randomObject : GeneratorSettings -> String -> Ref.SchemataPool -> List ( String, Schema ) -> List String -> Generator Value
randomObject settings ns pool props required =
    props
        |> List.foldl
            (\( k, v ) res ->
                if List.member k required then
                    v
                        |> valueGenerator (upgradeSettings settings) ns pool
                        |> Random.andThen (\x -> res |> Random.map ((::) ( k, x )))
                else
                    Random.float 0 1
                        |> Random.andThen
                            (\isRequired ->
                                if isRequired < settings.optionalPropertyProbability then
                                    v
                                        |> valueGenerator (upgradeSettings settings) ns pool
                                        |> Random.andThen (\x -> res |> Random.map ((::) ( k, x )))
                                else
                                    res
                            )
            )
            (Random.bool |> Random.map (\_ -> []))
        |> Random.map (List.reverse >> Encode.object)


randomList : GeneratorSettings -> String -> Ref.SchemataPool -> Int -> Int -> Schema -> Generator Value
randomList settings ns pool minItems maxItems schema =
    Random.int minItems maxItems
        |> Random.andThen (flip Random.list (valueGenerator (upgradeSettings settings) ns pool schema))
        |> Random.map (Encode.list)


{-|
Random value generator.

    buildSchema
        |> withProperties
            [ ( "foo", buildSchema |> withType "integer" ) ]
        |> toSchema
        |> Result.withDefault (blankSchema)
        |> value defaultSettings
        |> flip Random.step (Random.initialSeed 2)
        |> \( v, _ ) ->
            Expect.equal v (Encode.object [ ( "foo", Encode.int 688281600 ) ])

See tests for more examples.
-}
value : GeneratorSettings -> Schema -> Generator Value
value settings s =
    let
        ( pool, ns ) =
            collectIds s defaultPool
    in
        valueGenerator settings ns pool s


{-|
Random value generator at path.
-}
valueAt : GeneratorSettings -> Schema -> String -> Generator Value
valueAt settings s ref =
    let
        ( pool, ns ) =
            collectIds s defaultPool

        --|> Debug.log "pool is"
        a =
            pool
                |> Dict.keys
                |> Debug.log "pool keys are"
    in
        case Ref.resolveReference ns pool s ref of
            Just ( ns, ss ) ->
                valueGenerator settings ns pool ss

            Nothing ->
                nullGenerator


resolve : String -> Ref.SchemataPool -> Schema -> Maybe ( String, Schema )
resolve ns pool schema =
    case schema of
        BooleanSchema _ ->
            Just ( ns, schema )

        ObjectSchema os ->
            case os.ref of
                Just ref ->
                    Ref.resolveReference ns pool schema ref
                        |> Debug.log ("resolving this :( " ++ ref ++ " " ++ (toString ns))

                Nothing ->
                    Just ( ns, schema )


valueGenerator : GeneratorSettings -> String -> Ref.SchemataPool -> Schema -> Generator Value
valueGenerator settings ns pool schema =
    case schema |> resolve ns pool of
        Nothing ->
            nullGenerator

        Just ( ns, BooleanSchema b ) ->
            if b then
                Random.bool |> Random.map (\_ -> Encode.object [])
            else
                Random.bool |> Random.map (\_ -> Encode.null)

        Just ( ns, ObjectSchema os ) ->
            [ Maybe.andThen uncons os.examples
                |> Maybe.map randomItemFromList
            , Maybe.andThen uncons os.enum
                |> Maybe.map randomItemFromList
            , case os.type_ of
                SingleType NumberType ->
                    Random.float
                        (os.minimum |> Maybe.withDefault (toFloat Random.minInt))
                        (os.maximum |> Maybe.withDefault (toFloat Random.maxInt))
                        |> Random.map Encode.float
                        |> Just

                SingleType IntegerType ->
                    Random.int
                        (os.minimum |> Maybe.map round |> Maybe.withDefault Random.minInt)
                        (os.maximum |> Maybe.map round |> Maybe.withDefault Random.maxInt)
                        |> Random.map Encode.int
                        |> Just

                SingleType BooleanType ->
                    Random.bool
                        |> Random.map Encode.bool
                        |> Just

                SingleType StringType ->
                    randomString
                        (os.minLength |> Maybe.withDefault 0)
                        (os.maxLength |> Maybe.withDefault settings.defaultStringLengthLimit)
                        os.format
                        |> Random.map Encode.string
                        |> Just

                _ ->
                    Nothing
            , os.properties
                |> Maybe.map (\(Schemata props) -> randomObject settings ns pool props (os.required |> Maybe.withDefault []))
            , case os.items of
                ItemDefinition schema ->
                    randomList settings
                        ns
                        pool
                        (os.minItems |> Maybe.withDefault 0)
                        (os.maxItems |> Maybe.withDefault settings.defaultListLengthLimit)
                        schema
                        |> Just

                --NoItems ->
                _ ->
                    Nothing
            ]
                |> List.foldl
                    (\maybeGenerator res ->
                        if res == Nothing then
                            maybeGenerator
                        else
                            res
                    )
                    Nothing
                |> Maybe.withDefault (nullGenerator)
