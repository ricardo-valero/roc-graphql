interface Gql.Parser
    exposes []
    imports [
        ParserCore.{ Parser, map, map2, const, keep, skip, many, oneOrMore, sepBy1, maybe },
        ParserStr.{ RawStr, parseStr, strFromRaw, codeunit, codeunitSatisfies },
    ]

# Selection

Selection : [
    Field Field,
    # TODO: Fragments
]

selection : Parser RawStr Selection
selection =
    field |> map Field

selectionSet : Parser RawStr (List Selection)
selectionSet =
    const identity
    |> skip (codeunit '{')
    |> skip ignored
    |> keep (sepBy1 selection ignored)
    |> skip ignored
    |> skip (codeunit '}')

expect parseStr selectionSet "{}" |> Result.isErr
expect parseStr selectionSet "{name}" == Ok [sf "name"]
expect parseStr selectionSet "{ name }" == Ok [sf "name"]
expect parseStr selectionSet "{ name email }" == Ok [sf "name", sf "email"]
expect parseStr selectionSet "{ name\nemail }" == Ok [sf "name", sf "email"]
expect parseStr selectionSet "{ name, email }" == Ok [sf "name", sf "email"]
expect
    parseStr
        selectionSet
        """
        {
            fullName: name, 
              email
            phone
        }
        """
    == Ok [
        Field { field: "name", alias: Ok "fullName" },
        sf "email",
        sf "phone",
    ]
expect parseStr selectionSet "" |> Result.isErr
expect parseStr selectionSet "{name" |> Result.isErr
expect parseStr selectionSet "name}" |> Result.isErr

sf = \fname -> Field { field: fname, alias: Err Nothing }

# Field

Field : {
    field : Str,
    alias : Result Str [Nothing],
}

field : Parser RawStr Field
field =
    left, right <- map2 name (maybe colonAndFieldName)

    when right is
        Ok f ->
            { field: f, alias: Ok left }

        Err Nothing ->
            { field: left, alias: Err Nothing }

colonAndFieldName =
    const identity
    |> skip ignored
    |> skip (codeunit ':')
    |> skip ignored
    |> keep name

expect parseStr field "name" == Ok { field: "name", alias: Err Nothing }
expect parseStr field "fullName:name" == Ok { field: "name", alias: Ok "fullName" }
expect parseStr field "fullName: name" == Ok { field: "name", alias: Ok "fullName" }
expect parseStr field "fullName : name" == Ok { field: "name", alias: Ok "fullName" }

# Name

name : Parser RawStr Str
name =
    start, continue <- map2 nameStart nameContinue

    continue
    |> List.prepend start
    |> strFromRaw

expect parseStr name "name" == Ok "name"
expect parseStr name "productId" == Ok "productId"
expect parseStr name "User" == Ok "User"
expect parseStr name "__typename" == Ok "__typename"
expect parseStr name "users2" == Ok "users2"
expect parseStr name "2users" |> Result.isErr
expect parseStr name "product_id" == Ok "product_id"
expect parseStr name "product id" |> Result.isErr

nameStart =
    isAlpha
    |> orUnderscore
    |> codeunitSatisfies

nameContinue =
    isAlphanumeric
    |> orUnderscore
    |> codeunitSatisfies
    |> oneOrMore

orUnderscore = \option -> \code -> option code || code == '_'

isAlpha = \code ->
    (code >= 'A' && code <= 'Z') || (code >= 'a' && code <= 'z')

isNumeric = \code ->
    code >= '0' && code <= '9'

isAlphanumeric = \code ->
    isAlpha code || isNumeric code

# Helpers

ignored =
    # TODO: Comments
    many ignoredCodeunit

ignoredCodeunit =
    # TODO: Unicode BOM
    codeunitSatisfies \c ->
        (c == ' ')
        || (c == '\t')
        || (c == '\n')
        || (c == '\r')
        || (c == ',')

identity = \x -> x