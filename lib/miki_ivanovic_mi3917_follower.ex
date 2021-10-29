defmodule Follower do

def init state, term do
  state
  |> State.role(:FOLLOWER)
  |> State.curr_term(term)
  |> State.voted_for(nil)
  |> State.votes(0)
end # init

def next state, time do
  start_time  = DateTime.utc_now()
  curr_term   = state.curr_term

  receive do

    { :APPEND_ENTRIES_REQ, params } ->
       params = params
                |> Map.put(:total, time.total)
                |> Map.put(:remaining, time.remaining)
                |> Map.put(:start, start_time)
       { state, time } = AppendEntries.request state, params
       Server.next state, time

    { :VOTE_REQ, params } ->
       params = params
                |> Map.put(:total, time.total)
                |> Map.put(:remaining, time.remaining)
                |> Map.put(:start, start_time)
       { state, time } = Vote.request state, params
       Server.next state, time

    { :VOTE_REP, term, vote_granted } ->
       time = Map.put(time, :start, start_time)
       { state, time } = Vote.reply state, term, vote_granted, time
       Server.next state, time

    { :APPEND_ENTRIES_REP, term, _ } ->
       state = if term > curr_term do
                  Follower.init state, term
               else
                  state
               end
       Server.next(
        state, %{
           total: time.total,
           remaining: DAC.get_timeout(time.remaining, start_time)
         })

    { :CLIENT_REQUEST, _ } ->
      Server.next state, %{
        total: time.total,
        remaining: DAC.get_timeout(time.remaining, start_time)
       }

    { :PRINT } ->
      Monitor.state state, 1, ""
      Server.next state, %{
        total: time.total,
        remaining: DAC.get_timeout(time.remaining, start_time)
      }

    { :CRASH } ->
      IO.puts "Follower #{state.id} going to sleep for 1 second"
      Process.sleep(1000)
      IO.puts "Follower #{state.id} waking up"
      Server.next state, %{
        total: time.total,
        remaining: DAC.get_timeout(time.remaining, start_time)
      }

  after
    time.remaining ->
       state              = Candidate.init state
       election_timeout   = Enum.random state.config.election_timeout .. (2 * state.config.election_timeout)
       Server.next state, %{ total: election_timeout, remaining: election_timeout }
  end
end # next

end # Follower
