import gql from "graphql-tag";

export default gql`
  mutation {
    signOut {
      id
      username
    }
  }
`;