interface Gql.Parser
    exposes [selection]
    imports [
        ParserCore.{
            Parser,
            map,
            map2,
            fail,
            const,
            keep,
            skip,
            many,
            oneOrMore,
            sepBy1,
            maybe,
            andThen,
        },
        ParserStr.{
            RawStr,
            parseStr,
            strFromRaw,
            codeunit,
            codeunitSatisfies,
            oneOf,
            string,
        },
    ]

# Document

Document : List Definition

document : Parser RawStr Document
document =
    sepBy1 definition ignored

expect
    parseStr
        document
        """
        query GetUser {
            me {
                id
                name
            }
        }

        query {
            posts {
                id
                title
            }
        }
        """
    == Ok [
        Operation {
            type: Query,
            name: Ok "GetUser",
            selectionSet: [
                tf "me"
                |> ts [
                    tf "id",
                    tf "name",
                ],
            ],
        },
        Operation {
            type: Query,
            name: Err Nothing,
            selectionSet: [
                tf "posts"
                |> ts [
                    tf "id",
                    tf "title",
                ],
            ],
        },
    ]

# Definition

Definition : [
    Operation
        {
            type : OperationType,
            name : Result Str [Nothing],
            # TODO: Variable definitions
            # TODO: Directives
            selectionSet : List Selection,
        },
    Fragment
        {
            name : Str,
            typeName : Str,
            # TODO: Directives
            selectionSet : List Selection,
        },
]

definition : Parser RawStr Definition
definition =
    oneOf [
        operationDefinition,
        fragmentDefinition,
    ]

# Operation Definition

operationDefinition : Parser RawStr Definition
operationDefinition =
    const \type -> \nam -> \ss -> Operation { type, name: nam, selectionSet: ss }
    |> keep (maybe opType |> withDefault Query)
    |> skip ignored
    |> keep (maybe name)
    |> skip ignored
    |> keep selectionSet

OperationType : [Query, Mutation, Subscription]

opType : Parser RawStr OperationType
opType =
    oneOf [
        string "query" |> map \_ -> Query,
        string "mutation" |> map \_ -> Mutation,
        string "subscription" |> map \_ -> Subscription,
    ]

expect
    parseStr operationDefinition "query { user { id } }"
    == Ok
        (
            Operation {
                type: Query,
                name: Err Nothing,
                selectionSet: [tf "user" |> ts [tf "id"]],
            }
        )
expect
    parseStr operationDefinition "query GetUser { user { id } }"
    == Ok
        (
            Operation {
                type: Query,
                name: Ok "GetUser",
                selectionSet: [tf "user" |> ts [tf "id"]],
            }
        )
expect
    parseStr operationDefinition "mutation LogOut { logOut { success } }"
    == Ok
        (
            Operation {
                type: Mutation,
                name: Ok "LogOut",
                selectionSet: [tf "logOut" |> ts [tf "success"]],
            }
        )
expect
    parseStr operationDefinition "subscription { messages { id body } }"
    == Ok
        (
            Operation {
                type: Subscription,
                name: Err Nothing,
                selectionSet: [tf "messages" |> ts [tf "id", tf "body"]],
            }
        )
expect
    parseStr operationDefinition "{ user { id } }"
    == Ok
        (
            Operation {
                type: Query,
                name: Err Nothing,
                selectionSet: [tf "user" |> ts [tf "id"]],
            }
        )

# Fragment Definition

fragmentDefinition : Parser RawStr Definition
fragmentDefinition =
    const \fname -> \typeName -> \ss -> Fragment { name: fname, typeName, selectionSet: ss }
    |> skip (string "fragment")
    |> skip ignored
    |> keep fragmentName
    |> skip ignored
    |> skip (string "on")
    |> skip ignored
    |> keep name
    |> skip ignored
    |> keep selectionSet

expect
    parsed = parseStr fragmentDefinition "fragment UserDetails on User { id name posts { id, title } }"
    parsed
    == Ok
        (
            Fragment {
                name: "UserDetails",
                typeName: "User",
                selectionSet: [
                    tf "id",
                    tf "name",
                    tf "posts"
                    |> ts [
                        tf "id",
                        tf "title",
                    ],
                ],
            }
        )

fragmentName : Parser RawStr Str
fragmentName =
    fname <- name |> andThen

    if fname == "on" then
        fail "Fragment name must not be 'on'"
    else
        const fname

expect parseStr fragmentName "UserDetails" == Ok "UserDetails"
expect parseStr fragmentName "on" |> Result.isErr

# Selection

Selection : [
    Field
        {
            field : Str,
            alias : Result Str [Nothing],
            # TODO: Arguments
            # TODO: Directives
            selectionSet : List Selection,
        },
    # TODO: Fragments
]

selection : Parser RawStr Selection
selection =
    field

# Selection Set

selectionSet : Parser RawStr (List Selection)
selectionSet =
    const identity
    |> skip (codeunit '{')
    |> skip ignored
    |> keep (sepBy1 selection ignored)
    |> skip ignored
    |> skip (codeunit '}')

expect parseStr selectionSet "{}" |> Result.isErr
expect parseStr selectionSet "{name}" == Ok [tf "name"]
expect parseStr selectionSet "{ name }" == Ok [tf "name"]
expect parseStr selectionSet "{ name email }" == Ok [tf "name", tf "email"]
expect parseStr selectionSet "{ name\nemail }" == Ok [tf "name", tf "email"]
expect parseStr selectionSet "{ name, email }" == Ok [tf "name", tf "email"]
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
        tf "name" |> ta "fullName",
        tf "email",
        tf "phone",
    ]
expect parseStr selectionSet "" |> Result.isErr
expect parseStr selectionSet "{name" |> Result.isErr
expect parseStr selectionSet "name}" |> Result.isErr

# Field

field : Parser RawStr Selection
field =
    const \left -> \right -> \ss -> mkField left right ss
    |> keep name
    |> skip ignored
    |> keep (maybe colonAndFieldName)
    |> skip ignored
    |> keep (maybe definitelyNotSelectionSet |> withDefault [])

# Workaround for: https://github.com/roc-lang/roc/issues/5682
definitelyNotSelectionSet : Parser RawStr (List Selection)
definitelyNotSelectionSet =
    ParserCore.buildPrimitiveParser (\input -> ParserCore.parsePartial selectionSet input)

mkField = \left, right, ss ->
    when right is
        Ok f ->
            Field {
                field: f,
                alias: Ok left,
                selectionSet: ss,
            }

        Err Nothing ->
            Field {
                field: left,
                alias: Err Nothing,
                selectionSet: ss,
            }

colonAndFieldName =
    const identity
    |> skip (codeunit ':')
    |> skip ignored
    |> keep name

expect parseStr field "name" == Ok (tf "name")
expect parseStr field "fullName:name" == Ok (tf "name" |> ta "fullName")
expect parseStr field "fullName: name" == Ok (tf "name" |> ta "fullName")
expect parseStr field "fullName : name" == Ok (tf "name" |> ta "fullName")
expect parseStr field "user { name, age }" == Ok (tf "user" |> ts [tf "name", tf "age"])
expect
    parseStr field "viewer: user { id posts { id title } name }"
    == Ok
        (
            tf "user"
            |> ta "viewer"
            |> ts [
                tf "id",
                tf "posts" |> ts [tf "id", tf "title"],
                tf "name",
            ]
        )

# Value

Value : [
    Variable Str,
    IntValue I32,
    # TODO:
    # FloatValue
    # StringValue
    # BooleanValue
    # NullValue
    # EnumValue
    # ListValueConst
    # ObjectValue
]

value : Parser RawStr Value
value =
    oneOf [
        variable,
        intValue,
    ]

expect parseStr value "$id" == Ok (Variable "id")
expect parseStr value "123" == Ok (IntValue 123)
expect parseStr value "-456" == Ok (IntValue -456)

variable : Parser RawStr Value
variable =
    const Variable
    |> skip (codeunit '$')
    |> keep name

intValue : Parser RawStr Value
intValue =
    # TODO: Be more strict about leading zeroes
    const \neg -> \num -> if Result.isOk neg then IntValue -num else IntValue num
    |> keep (maybe (codeunit '-'))
    |> keep ParserStr.positiveInt

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

# Test field helpers

tf = \fname -> Field { field: fname, alias: Err Nothing, selectionSet: [] }
ts = \Field fiel, ss -> Field { fiel & selectionSet: ss }
ta = \Field fiel, alias -> Field { fiel & alias: Ok alias }

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

withDefault : Parser input (Result a [Nothing]), a -> Parser input a
withDefault = \parser, def ->
    parser |> map (\m -> Result.withDefault m def)
