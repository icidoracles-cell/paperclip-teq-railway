#!/bin/bash
set -e

if [ -d "/paperclip" ]; then
  chown -R paperclip:paperclip /paperclip 2>/dev/null || true
fi

exec gosu paperclip "$@"
