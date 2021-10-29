defmodule AppendEntries do

def reply state, server, term, success do
  curr_term     = state.curr_term
  next_index    = Map.get(state.next_index, server)
  match_index   = Map.get(state.match_index, server)
  cond do
    term > curr_term ->
      Follower.init state, term

    success == false ->
      State.next_index(state, server, max(0, next_index - 1))

    true ->
      state
      |> State.next_index(server, next_index + 1)
      |> State.match_index(server, match_index + 1)
  end
end

def request state, params do
  curr_term           = state.curr_term
  our_last_log_index  = length(state.log) - 1

  term            = params.term
  leader_id       = params.leader_id
  prev_log_index  = params.prev_log_index
  prev_log_term   = params.prev_log_term
  entries         = params.entries
  leader_commit   = params.leader_commit

  total           = params.total
  remaining       = params.remaining
  start           = params.start

  cond do
    term > curr_term ->
      AppendEntries.request Follower.init(state, term), params

    term < curr_term ->
      send leader_id, { :APPEND_ENTRIES_REP, curr_term, false }
      { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }

    prev_log_index > our_last_log_index ->
      send leader_id, { :APPEND_ENTRIES_REP, curr_term, false }
      { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }

    true ->
      if Enum.at(state.log, prev_log_index).term == prev_log_term do
         { old_logs, _ } = Enum.split(state.log, prev_log_index + 1)
         state = State.log(state, old_logs ++ entries)
         send leader_id, { :APPEND_ENTRIES_REP, curr_term, true }
         state = if leader_commit > state.commit_index do
                    index_of_last_new_entry = length(state.log) - 1
                    State.commit_index(state,
                      min(leader_commit, index_of_last_new_entry))
                 else
                    state
                 end
          { state, %{ total: total, remaining: total } }
      else
         send leader_id, { :APPEND_ENTRIES_REP, curr_term, false }
         { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }
      end
  end
end

end
