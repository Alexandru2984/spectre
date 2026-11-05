-module(spectre_link_test_ffi).
-export([retained_messages/1]).
retained_messages(Pid) -> map_size(maps:get(messages,sys:get_state(Pid))).
