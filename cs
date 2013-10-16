#!/usr/bin/env python
# create script
import os
import stat
import sys
envs = dict(py='python')
for filename in sys.argv[1:]:
    if not os.path.exists(filename):
        root, ext = os.path.splitext(filename)
        env = envs.get(ext[1:])
        head = '#!/bin/sh'
        if env:
            head = '#!/usr/bin/env %s' % (env)
        with open(filename, 'w') as f:
            f.write(head+'\n')
    filestat = os.stat(filename)
    os.chmod(filename, filestat.st_mode|stat.S_IXUSR|stat.S_IXGRP|stat.S_IXOTH)
