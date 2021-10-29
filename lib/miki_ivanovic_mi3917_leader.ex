defmodule Leader do

def init state do
  last_log_index  = length(state.log) - 1
  state           = state
                    |> State.role(:LEADER)
                    |> State.client_requests([])
                    |> State.next_index(Map.new)
                    |> State.match_index(Map.new)

  other_servers   = state.servers -- [state.selfP]

  state  = Enum.reduce(other_servers, state, fn server, acc ->
     State.next_index(acc, server, last_log_index + 1)
  end)
  state  = Enum.reduce(other_servers, state, fn server, acc ->
    State.match_index(acc, server, 1)
  end)

  state
end # init

def next state, time do

  curr_term       = state.curr_term
  commit_index    = state.commit_index
  last_log_index  = length(state.log) - 1
  majority        = state.majority

  # update commit index
  commit_index = Enum.reduce(commit_index .. last_log_index, commit_index, fn (n, acc) ->
    match_index_count = Enum.count(state.match_index, fn match_index -> match_index >= n end)
    log_term = Enum.at(state.log, n).term
    if match_index_count >= majority and log_term == curr_term do
       n
    else
       acc
    end
  end)

  state = State.commit_index(state, commit_index)

  # send append entries to followers:
  state = send_to_followers state

  # notify clients if their requests have been applied to state machine
  state = send_client_requests(state)

  start_time = DateTime.utc_now

  receive do

    { :CLIENT_REQUEST, request } ->
       Monitor.notify state, { :CLIENT_REQUEST, state.id }
       state = state
               |> State.log(state.log ++ [%{cmd: request.cmd, term: curr_term}])
               |> State.client_requests(state.client_requests ++ [%{index: last_log_index + 1, clientP: request.clientP}])
       Server.next(
        state, %{
           total: time.total,
           remaining: DAC.get_timeout(time.remaining, start_time)
         })

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

    { :PRINT } ->
      Monitor.state state, 1, ""
      Server.next state, %{
        total: time.total,
        remaining: DAC.get_timeout(time.remaining, start_time)
      }

    { :CRASH } ->
      IO.puts "Leader #{state.id} going to sleep for 1 second"
      Process.sleep(1000)
      IO.puts "Leader #{state.id} waking up"
      Server.next state, %{
        total: time.total,
        remaining: DAC.get_timeout(time.remaining, start_time)
      }

  after
    # After timeout add empty message to logs (heartbeat) and resend on next cycle
    time.remaining ->
      Server.next state, time
  end
end # next

defp send_to_followers state do
  followers = state.servers -- [state.selfP]
  curr_term = state.curr_term
  Enum.reduce(followers, state, fn (server, acc) ->
    last_log_index    = length(acc.log) - 1
    next_index        = Map.get(acc.next_index, server)
    prev_log_index    = next_index - 1
    prev_log_term     = Enum.at(acc.log, prev_log_index).term
    { _, entries }    = Enum.split acc.log, next_index

    params = %{
      term: curr_term,
      leader_id: acc.selfP,
      prev_log_index: prev_log_index,
      prev_log_term: prev_log_term,
      entries: entries,
      leader_commit: acc.commit_index,
    }
    if last_log_index >= next_index do
       send server, { :APPEND_ENTRIES_REQ, params }
       receive do
         { :APPEND_ENTRIES_REP, term, success } ->
            AppendEntries.reply acc, server, term, success
       after
         state.config.append_entries_timeout -> acc
       end
    else
       acc
    end
  end)
end # send_to_followers

defp send_client_requests(state) do
  commit_index  = state.commit_index
  requests      = state.client_requests

  if not Enum.empty?(requests) do
    request = hd(requests)
    if request.index <= commit_index do
      send request.clientP, { :CLIENT_REPLY, %{ leaderP: state.selfP }}
      send_client_requests(State.client_requests(state, tl(requests)))
    else
      state
    end
  else
    state
  end
end

end # Leader
