module Json.Schema.Definitions
    exposing
        ( Schema(ObjectSchema, BooleanSchema)
        , Schemata(Schemata)
        , Type(AnyType, SingleType, NullableType, UnionType)
        , SingleType(IntegerType, NumberType, StringType, BooleanType, NullType, ArrayType, ObjectType)
        , stringToType
        , blankSchema
        , blankSubSchema
        , decoder
        , SubSchema
        , Items(ItemDefinition, ArrayOfItems, NoItems)
        , Dependency(ArrayPropNames, PropSchema)
        )

import Util exposing (resultToDecoder, foldResults, isInt)
import Json.Decode.Pipeline exposing (decode, optional)
import Json.Decode as Decode
    exposing
        ( Value
        , Decoder
        , succeed
        , fail
        , lazy
        , maybe
        , nullable
        , field
        , andThen
        , string
        , float
        , int
        , bool
        , list
        , value
        )


type Schema
    = BooleanSchema Bool
    | ObjectSchema SubSchema


type alias SubSchema =
    { type_ : Type
    , id : Maybe String
    , ref : Maybe String
    -- meta
    , title : Maybe String
    , description : Maybe String
    , default : Maybe Value
    , examples : Maybe (List Value)
    , definitions : Maybe Schemata
    -- numeric validations
    , multipleOf : Maybe Float
    , maximum : Maybe Float
    , exclusiveMaximum : Maybe Float
    , minimum : Maybe Float
    , exclusiveMinimum : Maybe Float
    -- string validations
    , maxLength : Maybe Int
    , minLength : Maybe Int
    , pattern : Maybe String
    , format : Maybe String
    -- array validations
    , items : Items
    , additionalItems : Maybe Schema
    , maxItems : Maybe Int
    , minItems : Maybe Int
    , uniqueItems : Maybe Bool
    , contains : Maybe Schema
    , maxProperties : Maybe Int
    , minProperties : Maybe Int
    , required : Maybe (List String)
    , properties : Maybe Schemata
    , patternProperties : Maybe Schemata
    , additionalProperties : Maybe Schema
    , dependencies : List (String, Dependency)
    , propertyNames : Maybe Schema
    , enum : Maybe (List Value)
    , const : Maybe Value
    , allOf : Maybe (List Schema)
    , anyOf : Maybe (List Schema)
    , oneOf : Maybe (List Schema)
    , not : Maybe Schema
    }


blankSchema : Schema
blankSchema = ObjectSchema blankSubSchema

blankSubSchema : SubSchema
blankSubSchema =
    { type_ = AnyType
    , id = Nothing
    , ref = Nothing
    , title = Nothing
    , description = Nothing
    , default = Nothing
    , examples = Nothing
    , definitions = Nothing
    , multipleOf = Nothing
    , maximum = Nothing
    , exclusiveMaximum = Nothing
    , minimum = Nothing
    , exclusiveMinimum = Nothing
    , maxLength = Nothing
    , minLength = Nothing
    , pattern = Nothing
    , format = Nothing
    , items = NoItems
    , additionalItems = Nothing
    , maxItems = Nothing
    , minItems = Nothing
    , uniqueItems = Nothing
    , contains = Nothing
    , maxProperties = Nothing
    , minProperties = Nothing
    , required = Nothing
    , properties = Nothing
    , patternProperties = Nothing
    , additionalProperties = Nothing
    , dependencies = []
    , propertyNames = Nothing
    , enum = Nothing
    , const = Nothing
    , allOf = Nothing
    , anyOf = Nothing
    , oneOf = Nothing
    , not = Nothing
    }


type Schemata
    = Schemata (List ( String, Schema ))


type Items
    = NoItems
    | ItemDefinition Schema
    | ArrayOfItems (List Schema)

type Dependency
    = ArrayPropNames (List String)
    | PropSchema Schema


decoder : Decoder Schema
decoder =
    let
        singleType =
            string
                |> andThen singleTypeDecoder

        multipleTypes =
            string
                |> list
                |> andThen multipleTypesDecoder

        booleanSchemaDecoder =
            Decode.bool
                |> Decode.andThen (\b ->
                    if b then
                        succeed (BooleanSchema True)
                    else
                        succeed (BooleanSchema False)
                )

        objectSchemaDecoder =
            decode SubSchema
                |> optional "type"
                    (Decode.oneOf [ multipleTypes, Decode.map SingleType singleType ])
                    AnyType
                |> optional "id" (nullable string) Nothing
                |> optional "$ref" (nullable string) Nothing
                -- meta
                |> optional "title" (nullable string) Nothing
                |> optional "description" (nullable string) Nothing
                |> optional "default" (nullable value) Nothing
                |> optional "examples" (nullable <| list value) Nothing
                |> optional "definitions" (nullable <| lazy <| \_ -> schemataDecoder) Nothing
                -- number
                |> optional "multipleOf" (nullable float) Nothing
                |> optional "maximum" (nullable float) Nothing
                |> optional "exclusiveMaximum" (nullable float) Nothing
                |> optional "minimum" (nullable float) Nothing
                |> optional "exclusiveMinimum" (nullable float) Nothing
                -- string
                |> optional "maxLength" (nullable nonNegativeInt) Nothing
                |> optional "minLength" (nullable nonNegativeInt) Nothing
                |> optional "pattern" (nullable string) Nothing
                |> optional "format" (nullable string) Nothing
                -- array
                |> optional "items" (lazy (\_ -> itemsDecoder)) NoItems
                |> optional "additionalItems" (nullable <| lazy (\_ -> decoder)) Nothing
                |> optional "maxItems" (nullable nonNegativeInt) Nothing
                |> optional "minItems" (nullable nonNegativeInt) Nothing
                |> optional "uniqueItems" (nullable bool) Nothing
                |> optional "contains" (nullable <| lazy (\_ -> decoder)) Nothing
                |> optional "maxProperties" (nullable nonNegativeInt) Nothing
                |> optional "minProperties" (nullable nonNegativeInt) Nothing
                |> optional "required" (nullable (list string)) Nothing
                |> optional "properties" (nullable (lazy (\_ -> schemataDecoder))) Nothing
                |> optional "patternProperties" (nullable (lazy (\_ -> schemataDecoder))) Nothing
                |> optional "additionalProperties" (nullable <| lazy (\_ -> decoder)) Nothing
                |> optional "dependencies" (lazy (\_ -> dependenciesDecoder)) []
                |> optional "propertyNames" (nullable <| lazy (\_ -> decoder)) Nothing
                |> optional "enum" (nullable nonEmptyUniqueArrayOfValuesDecoder) Nothing
                |> optional "const" (nullable value) Nothing
                |> optional "allOf" (nullable (lazy (\_ -> nonEmptyListOfSchemas))) Nothing
                |> optional "anyOf" (nullable (lazy (\_ -> nonEmptyListOfSchemas))) Nothing
                |> optional "oneOf" (nullable (lazy (\_ -> nonEmptyListOfSchemas))) Nothing
                |> optional "not" (nullable <| lazy (\_ -> decoder)) Nothing
    in
        Decode.oneOf
            [ booleanSchemaDecoder
            , objectSchemaDecoder
                |> Decode.andThen (\b ->
                    succeed (ObjectSchema b)
                )
            ]



nonEmptyListOfSchemas : Decoder (List Schema)
nonEmptyListOfSchemas =
    list (lazy (\_ -> decoder))
        |> andThen failIfEmpty


nonEmptyUniqueArrayOfValuesDecoder : Decoder (List Value)
nonEmptyUniqueArrayOfValuesDecoder =
    list value
        |> andThen failIfValuesAreNotUnique
        |> andThen failIfEmpty


failIfValuesAreNotUnique : List Value -> Decoder (List Value)
failIfValuesAreNotUnique l =
    succeed l


failIfEmpty : List a -> Decoder (List a)
failIfEmpty l =
    if List.isEmpty l then
        fail "List is empty"
    else
        succeed l


itemsDecoder : Decoder Items
itemsDecoder =
    Decode.oneOf
        [ Decode.map ArrayOfItems <| list decoder
        , Decode.map ItemDefinition decoder
        ]


dependenciesDecoder : Decoder (List (String, Dependency))
dependenciesDecoder =
    Decode.oneOf
        [ Decode.map ArrayPropNames (list string)
        , Decode.map PropSchema decoder
        ]
            |> Decode.keyValuePairs


nonNegativeInt : Decoder Int
nonNegativeInt =
    int
        |> andThen (\x -> if x >= 0 && isInt x then succeed x else fail "Expected non-negative int")


type Type
    = AnyType
    | SingleType SingleType
    | NullableType SingleType
    | UnionType (List SingleType)


type SingleType
    = IntegerType
    | NumberType
    | StringType
    | BooleanType
    | ArrayType
    | ObjectType
    | NullType


multipleTypesDecoder : List String -> Decoder Type
multipleTypesDecoder lst =
    case lst of
        [ x, "null" ] ->
            Decode.map NullableType <| singleTypeDecoder x

        [ "null", x ] ->
            Decode.map NullableType <| singleTypeDecoder x

        [ x ] ->
            Decode.map SingleType <| singleTypeDecoder x

        otherList ->
            otherList
                |> List.sort
                |> List.map stringToType
                |> foldResults
                |> Result.andThen (Ok << UnionType)
                |> resultToDecoder



stringToType : String -> Result String SingleType
stringToType s =
    case s of
        "integer" ->
            Ok IntegerType

        "number" ->
            Ok NumberType

        "string" ->
            Ok StringType

        "boolean" ->
            Ok BooleanType

        "array" ->
            Ok ArrayType

        "object" ->
            Ok ObjectType

        "null" ->
            Ok NullType

        _ ->
            Err ("Unknown type: " ++ s)


singleTypeDecoder : String -> Decoder SingleType
singleTypeDecoder s =
    case stringToType s of
        Ok st ->
            succeed st

        Err msg ->
            fail msg


schemataDecoder : Decoder Schemata
schemataDecoder =
    Decode.map Schemata <| Decode.keyValuePairs (lazy (\_ -> decoder))