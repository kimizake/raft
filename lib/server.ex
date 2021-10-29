
# distributed algorithms, n.dulay, 4 feb 2020
# coursework, raft consenus, v1

defmodule Server do

# using: s for 'server/state', m for 'message'

def start(config, server_id, databaseP) do
  receive do
  { :BIND, servers } ->
    s = State.initialise(config, server_id, servers, databaseP)
    t = Map.get(config.crash_servers, s.id)
    if t != nil do
      Process.send_after(s.selfP, { :CRASH }, t)
    end
   _s = Server.next(s)
  end # receive
end # start

def next(s) do
  # Process.send_after(self(), { :PRINT }, 8000)
  timeout = Enum.random s.config.election_timeout .. (2 * s.config.election_timeout)
  next s, %{ total: timeout, remaining: timeout }
end # next/1

def next(s, timeout) do
  s = apply_to_state_machine(s, s.commit_index - s.last_applied)
  # Monitor.state s, 10, "  "
  case s.role do
    :LEADER -> Leader.next s, timeout
    :CANDIDATE -> Candidate.next s, timeout
    :FOLLOWER -> Follower.next s, timeout
  end
end # next/2

defp apply_to_state_machine(state, diff) when diff <= 0, do: state

defp apply_to_state_machine(state, diff) do
  state   = State.last_applied(state, state.last_applied + 1)
  log     = Enum.at(state.log, state.last_applied)
  send state.databaseP, { :EXECUTE, log.cmd }
  apply_to_state_machine(state, diff - 1)
end

end # Server
