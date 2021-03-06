defmodule Bullsource.Votes.ProofVoteDown do
  use Ecto.Schema

  alias Bullsource.Discussion.Proof
  alias Bullsource.Accounts.User

  schema "proof_votes_down" do
    belongs_to :proof, Proof
    belongs_to :user, User

    timestamps()

  end
end