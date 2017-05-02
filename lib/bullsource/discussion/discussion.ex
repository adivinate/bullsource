defmodule Bullsource.Discussion do
  import Ecto.{Changeset, Query}
  alias Bullsource.Discussion.{Article, Comment, Post, Proof, Reference, Thread, Topic, ProofReference}
  alias Bullsource.Accounts.User
  alias Bullsource.Repo
  alias Ecto.Multi


  def list_topics do
    Repo.all(Topic) |> Repo.preload(:threads)
  end

  def create_topic(params) do
    topic_changeset(params) |> Repo.insert
  end

# will list nested threads in topics with the users who created it. I wonder if [threads: :user] works.
  def list_threads_in_topic(topic_id) do
    Repo.get(Topic,topic_id) |> Repo.preload([{:threads, :user}])
  end

  def list_posts_in_thread(thread_id) do
    Repo.get(Thread,thread_id) |> Repo.preload(:user) |> Repo.preload(posts: [proofs: :article, proofs: :comment, proofs: :references])
  end

  ####creating interface functions for controllers.
  #is it possible to chain transactions at a higher order?
  #the reason for all the multis is for the rollback functionality in case anything in the chain is invalid.

  def create_thread(thread, post, user) do
    IO.puts "+++++thread:"
    IO.inspect thread
    IO.puts "+++++post:"
    IO.inspect post
    IO.puts "+++++user:"
    IO.inspect user
    case thread_transaction(thread, post, user) |> Repo.transaction do
        {:ok, %{thread: finished_thread} = new_thread} ->
          IO.puts "+++++++++++++++++++++create_thread"
          IO.inspect new_thread
          {:ok,
               finished_thread
               |> Repo.preload(:user)
               |> Repo.preload(posts: [proofs: :article, proofs: :comment, proofs: :references])
          }
        {:error, _, reason, _} ->
          IO.puts "++++thread_transaction error:+++++"
          IO.inspect reason
          {:error, reason}
    end
  end

  #create_post?

  defp create_proofs(post, proofs) do
  IO.puts "create_proofs: ++++++++ post"
  IO.inspect post
  IO.puts "create_proofs: ++++++++ proofs"
  IO.inspect proofs
   case proofs_transaction(post, proofs) |> Repo.transaction do
     {:ok, proofs} -> {:ok, proofs}
     {:error, _, reason, _} -> {:error, reason}
   end
  end

  defp create_proof_details(proof, proof_content) do
    case proof_details_transaction(proof, proof_content) |> Repo.transaction do
      {:ok, post_with_proofs} ->
        IO.puts "post_with proofs: ++++++"
        IO.inspect post_with_proofs
        {:ok, post_with_proofs}

      {:error, _, reason, _} -> {:error, reason}
    end
  end

  ####Ecto.Multi functions

  def thread_transaction(thread, post, user) do
    Multi.new
    |> Multi.insert(:thread, thread_changeset(%{topic_id: thread.topic_id, user_id: user.id, title: thread.title}))
    |> Multi.run(:post,   &insert_post(&1.thread, post, user))
    |> Multi.run(:proofs, &create_proofs(&1.post, post.proofs))
    #maybe just keep pipelining the multis, and using enum.map for the proofs? I think there may be a complication because it's another Multi.new in create_proofs.
  end

  defp proofs_transaction(post, proofs) do
    Multi.new
    |> Multi.insert(:proof, proof_changeset(%{post_id: post.id}))
    |> Multi.run(:proof_chain, &insert_proofs(&1.proof, proofs))
  end

  defp proof_details_transaction(proof, proof_content) do
    Multi.new
    |> Multi.insert(:article, article_changeset(%{proof_id: proof.id, text: proof_content.article}))
    |> Multi.insert(:comment, comment_changeset(%{proof_id: proof.id, text: proof_content.comment}))
    |> Multi.insert(:reference,
      reference_changeset(%{link: proof_content.reference.link,title: proof_content.reference.title}))
    |> Multi.run(:proof_reference, &insert_proof_reference(proof, &1.reference))
  end

  defp insert_thread(thread, user) do
    thread_changeset(%{user_id: user.id, topic_id: thread.topic_id, title: thread.title})
    |> Repo.insert
  end

  defp insert_post(thread, post, user) do
    IO.puts "in insert_post, thread++++++:"
    IO.inspect thread
    IO.puts "in insert_post, post++++++:"
    IO.inspect post

    post_changeset(%{intro: post.intro, user_id: user.id, thread_id: thread.id})
    |> Repo.insert
  end

  defp insert_post_proof(post) do
    proof_changeset(%{post_id: post.id})
    |> Repo.insert
  end

#so far, post_proof will have the id of the post. We will see if there's already a link available for the reference.
  defp insert_proofs(proof, [first_proof_content | rest_proofs_content]) do

    reference = Repo.get_by(Reference, link: first_proof_content.reference.link)
    case reference do
      nil ->
      IO.puts "nil'd ++++++++++++"
        case create_proof_details(proof, first_proof_content) do
          {:ok, proof_detail} ->
            #add the previous proof details that have finished:
            #proof_details = proof_details ++ proof_detail
            insert_proofs(proof, rest_proofs_content) #recursion.

          {:error, reason} ->
            {:error, reason} #these tuples are very much DRY right now, will need refactor
        end

      reference ->
      IO.puts "reference'd+++++++++++++ #{reference}'"
#      may have to query to get the proof_id/similar to post_proof
        case create_proof_details(reference, first_proof_content) do
          {:ok, proof_detail} ->
            #add the previous proof details that have finished:
            #proof_details = proof_details ++ proof_detail
            insert_proofs(proof, rest_proofs_content) #recursion.

          {:error, reason} ->
            {:error, reason} #these tuples are very much DRY right now, will need refactor
        end
    end
  end

# recursion end here
  defp insert_proofs(proof, []) do
  #should be a query that will return a preloaded tuple.
    {:ok, proof}
  end

  defp insert_article(proof, article) do
    article_changeset(%{proof_id: post_proof.id, text: article.text}) |> Repo.insert
  end

  defp insert_comment(proof, comment) do
    article_changeset(%{proof_id: post_proof.id, text: comment.text}) |> Repo.insert
  end

# remember that you want to check if it exists first before you run this function.
  defp insert_reference(reference) do
    article_changeset(%{link: reference.link, title: reference.title}) |> Repo.insert
  end

  defp insert_proof_reference(post_proof, reference) do
    proof_reference_changeset(%{proof_id: post_proof.id, reference_id: reference.id})
    |> Repo.insert
  end

##### Changesets #####

  def topic_changeset(params \\ %{}) do
    %Topic{}
    |> cast(params, [:name, :description])
    |> validate_required([:name, :description])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_]*$/)
    |> validate_length(:name, max: 32)
    |> validate_length(:name, min: 1)
    |> validate_length(:description, max: 140)
    |> validate_length(:description, min: 1)
    |> unique_constraint(:name)
  end

  def thread_changeset(params \\ %{}) do
    %Thread{}
    |> cast(params, [:title, :user_id, :topic_id])
    |> validate_required([:title, :user_id, :topic_id])
    |> validate_length(:title, max: 300)
    |> validate_length(:title, min: 3)
    |> assoc_constraint(:topic)
    |> assoc_constraint(:user)
  end

  def post_changeset(params \\ %{}) do
    %Post{}
    |> cast(params, [:intro, :user_id, :thread_id])
    |> validate_required([:user_id, :thread_id])
    |> validate_length(:intro, min: 3)
    |> validate_length(:intro, max: 500)
    |> assoc_constraint(:thread)
    |> assoc_constraint(:user)
  end

  def proof_changeset(params \\ %{}) do
    %Proof{}
    |> cast(params, [:post_id])
    |> validate_required([:post_id])
    |> assoc_constraint(:post)
  end

  #the article is a section of the reference that they're quoting.
  def article_changeset(params \\ %{}) do
    %Article{}
    |> cast(params, [:text, :proof_id])
    |> validate_required([:text, :proof_id])
    |> assoc_constraint(:proof)
  end

  def comment_changeset(params \\ %{}) do
    %Comment{}
    |> cast(params, [:text, :proof_id])
    |> validate_required([:proof_id])
    |> validate_length(:text, max: 500)
    |> assoc_constraint(:proof)
  end

  def reference_changeset(params \\ %{}) do
    %Reference{}
    |> cast(params, [:title, :link])
    |> validate_required([:link])
    |> validate_length(:title, max: 300)
  end

  def proof_reference_changeset(params \\ %{}) do
    %ProofReference{}
    |> cast(params, [:proof_id, :reference_id])
    |> validate_required([:proof_id, :reference_id])
    |> assoc_constraint(:proof)
    |> assoc_constraint(:reference)
  end

end