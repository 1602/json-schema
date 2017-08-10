module Data.Schema
    exposing
        ( Schema
        , Validation(IntegerSchema, FloatSchema, StringSchema, Undefined)
        , Schemata(Schemata)
        , Meta
        , decoder
        , Type(AnyType, SingleType, NullableType, UnionType)
        , SingleType(IntegerType, NumberType, StringType, NullType, ArrayType, ObjectType)
        , stringToType
        , blankSchema
        )

import Util exposing (resultToDecoder, foldResults)
import Data.NumberValidations as NumberValidations exposing (NumberValidations)
import Data.StringValidations as StringValidations exposing (StringValidations)
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
        , list
        , value
        )
import Json.Decode.Pipeline exposing (decode, optional)


type alias Schema =
    { type_ : Type
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
    -- array validations
    , items : Maybe Items
    }


blankSchema =
    { type_ = Nothing
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
    , items = Nothing
    }

type Schemata
    = Schemata (List ( String, Schema ))


type Items
    = ItemDefinition Schema
    | ArrayOfItems (List Schema)


type Validation
    = IntegerSchema NumberValidations
    | FloatSchema NumberValidations
    | StringSchema StringValidations
    | ArraySchema ArrayValidations
    | Undefined NumberValidations StringValidations


type alias ArrayValidations =
    { items : Maybe Items
    }


arrayValidationsDecoder : Decoder ArrayValidations
arrayValidationsDecoder =
    Decode.map ArrayValidations
        (maybe <| field "items" itemsDecoder)


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
    in
        decode Schema
            |> optional "type"
                (Decode.oneOf [ multipleTypes, Decode.map SingleType singleType ])
                AnyType
            |> optional "title" (nullable string) Nothing
            -- meta
            |> optional "description" (nullable string) Nothing
            |> optional "default" (nullable value) Nothing
            |> optional "examples" (nullable <| list value) Nothing
            |> optional "definitions" (nullable schemataDecoder) Nothing
            -- number
            |> optional "multipleOf" (nullable float) Nothing
            |> optional "maximum" (nullable float) Nothing
            |> optional "exclusiveMaximum" (nullable float) Nothing
            |> optional "minimum" (nullable float) Nothing
            |> optional "exclusiveMinimum" (nullable float) Nothing
            -- string
            |> optional "maxLength" (nullable int) Nothing
            |> optional "minLength" (nullable int) Nothing
            |> optional "pattern" (nullable string) Nothing
            -- array
            |> optional "items" (nullable itemsDecoder) Nothing





itemsDecoder : Decoder Items
itemsDecoder =
    Decode.oneOf
        [ Decode.map ItemDefinition <| lazy <| \_ -> decoder
        , Decode.map ArrayOfItems (list <| lazy <| \_ -> decoder)
        ]


type Type
    = AnyType
    | SingleType SingleType
    | NullableType SingleType
    | UnionType (List SingleType)


type SingleType
    = IntegerType
    | NumberType
    | StringType
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


type alias Meta =
    { title : Maybe String
    , description : Maybe String
    , default : Maybe Value
    , examples : Maybe (List Value)
    }


metaDecoder : Decoder Meta
metaDecoder =
    Decode.map4 Meta
        (maybe <| field "title" string)
        (maybe <| field "description" string)
        (maybe <| field "default" value)
        (maybe <| field "examples" <| list value)


schemataDecoder : Decoder Schemata
schemataDecoder =
    Decode.map Schemata <| Decode.keyValuePairs (lazy (\_ -> decoder))
