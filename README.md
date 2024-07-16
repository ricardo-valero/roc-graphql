# roc-graphql

GraphQL in Roc experiment

## ⚠️ WIP

Originally from https://github.com/agu-z/roc-gql

## Example

1. Run the server:

```shell
$ roc examples/posts.roc
```

2. Point your prefered GraphQL playground app (such as [Altair](https://altairgraphql.dev)) to [http://localhost:8000](http://localhost:8000) and run a query!

### Example query

```graphql
query {
  posts {
    ...PostBasics
  }

  postNumberOne: post(id: 1) {
    ...PostBasics
    body
    author {
      firstName
      lastName
    }
  }
}

fragment PostBasics on Post {
  id
  title
  section
}
```
