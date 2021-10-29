defmodule Vote do

def reply state, term, vote_granted, time do
  curr_term   = state.curr_term
  majority    = state.majority
  role        = state.role

  total       = time.total
  remaining   = time.remaining
  start       = time.start

  cond do
    term > curr_term ->
      Vote.reply Follower.init(state, term), term, vote_granted, time

    role != :CANDIDATE ->
      { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }

    vote_granted == false ->
      { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }

    true ->
      state = State.votes(state, state.votes + 1)
      if state.votes >= majority do
        # time = Enum.random state.config.append_entries_timeout .. state.config.election_timeout
        time = state.config.election_timeout
        { Leader.init(state), %{ total: time, remaining: time } }
      else
        { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }
      end
  end
end

def request state, params do
  curr_term           = state.curr_term
  voted_for           = state.voted_for
  our_last_log_index  = length(state.log) - 1
  our_last_log_term   = List.last(state.log).term

  term            = params.term
  candidate_id    = params.candidate_id
  last_log_index  = params.last_log_index
  last_log_term   = params.last_log_term

  total           = params.total
  remaining       = params.remaining
  start           = params.start

  cond do
    term > curr_term ->
      Vote.request Follower.init(state, term), params

    term < curr_term ->
      send candidate_id, { :VOTE_REP, curr_term, false}
      { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }

    voted_for != nil and voted_for != candidate_id ->
      send candidate_id, { :VOTE_REP, curr_term, false}
      { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }

    true ->
      success = last_log_term > our_last_log_term or
                (last_log_term == our_last_log_term and
                 last_log_index >= our_last_log_index)
      send candidate_id, { :VOTE_REP, curr_term, success }
      if success do
         state = state
                 |> Follower.init(term)
                 |> State.voted_for(candidate_id)
         { state, %{ total: total, remaining: total } }
      else
         { state, %{ total: total, remaining: DAC.get_timeout(remaining, start) } }
      end
  end
end

end
