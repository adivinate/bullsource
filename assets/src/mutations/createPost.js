import gql from "graphql-tag";

export default gql`
 mutation CreatePost($thread_id: Int!, $post: InputPost!){
  createPost(threadId: $thread_id, post:{
    proofs:[{
      article: "4th proof in thread, 1st proof in 2nd article",
      comment: "4th proof in thread, 1st proof in 2nd comment",
      reference: {
        link: "http://snapchat.com",
        title: "graphql createpost3 title"
      }
    }],
    intro: "4th post in first graphql thread, made from createPost mutation."
  }){
    id
    upVotes{
      user{
        id
        username
      }
    }
  }
}
`;