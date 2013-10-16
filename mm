#!/usr/bin/env python
# Create a Makefile.

import argparse
import os
import re

IGNORE = ['.git']
INCEXTS = ['.h', '.hpp']
SRCEXTS = ['.c', '.cc', '.cpp', '.m']

parser = argparse.ArgumentParser()
parser.add_argument('-b', default='a.out')
parser.add_argument('-s', default='.')
parser.add_argument('-i', default='.')
parser.add_argument('-o', default='.')
args = parser.parse_args()

def extract_includes(path):
    with open(path) as f:
        return re.findall('#(?:include|import) \"(.*)\"', f.read(), re.MULTILINE)

cflags = ['-O2', '-Wall', '-ansi', '-pedantic']
ldflags = ['-lm']
incs = {}
objs = {}
srcs = {}
incdirs = []
tree = []

for dirpath, dirnames, filenames in os.walk(args.i):
    cflags.append('-I %s' % (dirpath))
    for dirname in IGNORE:
        if dirname in dirnames:
            del dirnames[dirnames.index(dirname)]
    for filename in filenames:
        name, ext = os.path.splitext(filename)
        filepath = os.path.join(dirpath, filename)
        if ext in INCEXTS:
            inctarget = os.path.relpath(filepath, '.')
            incs[filename] = inctarget

for dirpath, dirnames, filenames in os.walk(args.s):
    for dirname in IGNORE:
        if dirname in dirnames:
            del dirnames[dirnames.index(dirname)]
    for filename in filenames:
        name, ext = os.path.splitext(filename)
        filepath = os.path.join(dirpath, filename)
        srctarget = os.path.relpath(filepath, '.')
        if ext in SRCEXTS:
            obj = os.path.join(args.o, ''.join((name, '.o')))
            objtarget = os.path.relpath(obj, '.')
            deps = extract_includes(filepath)
            deps = [incs[dep] for dep in deps]
            branch = (objtarget, srctarget, deps)
            tree.append(branch)

print 'MKDIR=mkdir -p'
print 'RMDIR=rmdir'
print 'CFLAGS=%s' % ' '.join(cflags)
print 'LDFLAGS=%s' % ' '.join(ldflags)
print
print 'all: %s %s\n' % (args.o if args.o else '', args.b)

objs = ' '.join(obj for obj, src, incs in tree)

# obj dir
if args.o:
    print '%s:\n\t$(MKDIR) %s' % (args.o, args.o)
    print

# link
print '%s: %s\n\t$(CC) $(LDFLAGS) -o $@ $+\n' % (args.b, objs)

# compile
for obj, src, incs in tree:
    print '%s: %s %s' % (obj, src, ' '.join(incs))
    print '\t$(CC) $(CFLAGS) -c -o $@ %s\n' % (src)

# clean
print 'clean:\n\t$(RM) %s %s' % (args.b, objs)
if args.o:
    print '\t$(RMDIR) %s' % (args.o)
