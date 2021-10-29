defmodule Candidate do

def init state do
  state            = state
                     |> State.role(:CANDIDATE)
                     |> State.curr_term(state.curr_term + 1)
                     |> State.voted_for(state.selfP)
                     |> State.votes(1)
  last_log_index   = length(state.log) - 1
  last_log_term    = List.last(state.log).term
  other_servers    = state.servers -- [state.selfP]
  params           = %{
      term: state.curr_term,
      candidate_id: state.selfP,
      last_log_index: last_log_index,
      last_log_term: last_log_term
    }

  Enum.map(other_servers, fn server ->
    send server, { :VOTE_REQ, params }
  end)

  state
end # init

def next state, time do
  start_time        = DateTime.utc_now()
  curr_term         = state.curr_term

  receive do

    { :VOTE_REP, term, vote_granted } ->
       time = Map.put(time, :start, start_time)
       { state, time } = Vote.reply state, term, vote_granted, time
       Server.next state, time

    { :VOTE_REQ, params } ->
       params = params
                |> Map.put(:total, time.total)
                |> Map.put(:remaining, time.remaining)
                |> Map.put(:start, start_time)
       { state, time } = Vote.request state, params
       Server.next state, time

    { :APPEND_ENTRIES_REQ, params } ->
       params = params
                |> Map.put(:total, time.total)
                |> Map.put(:remaining, time.remaining)
                |> Map.put(:start, start_time)
       { state, time } = AppendEntries.request state, params
       Server.next state, time

    { :APPEND_ENTRIES_REP, term, _ } ->
       state = if term > curr_term do
                  Follower.init state, term
               else
                  state
               end
       Server.next state, %{
         total: time.total,
         remaining: DAC.get_timeout(time.remaining, start_time)
       }

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
      IO.puts "Candidate #{state.id} going to sleep for 1 second"
      Process.sleep(1000)
      IO.puts "Candidate #{state.id} waking up"
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

end # Candidate
