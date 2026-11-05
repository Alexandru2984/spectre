#!/usr/bin/env python3
"""Refuse to run isolated test mutations against a pre-existing listener."""
import socket
import sys

port = int(sys.argv[1])
assert port in (4400, 4402), 'Only the reserved test ports are supported.'
with socket.socket() as probe:
    try:
        probe.bind(('127.0.0.1', port))
    except OSError:
        sys.exit(f'Port {port} is occupied. Stop the intended test instance or use a clean environment; no other service will be stopped automatically.')
