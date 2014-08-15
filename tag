#!/usr/bin/env python

"""Tag files."""

import argparse
import hashlib
import os
import sqlite3
import sys
import threading

from collections import defaultdict

from PIL import Image
import SimpleHTTPServer

REPONAME = '.tag'
DATANAME = 'db'
THUMBSNAME = 'thumbs'
IGNORE_FILENAMES = [REPONAME]

def find_repopath():
    dirpath = os.path.abspath('.')
    while dirpath != os.sep:
        repopath = os.path.join(dirpath, REPONAME)
        if os.path.exists(repopath):
            return repopath
        dirpath, dirname = os.path.split(dirpath)
    return None

REPOPATH = find_repopath()
REPOROOT = REPOPATH and os.path.split(REPOPATH)[0]
DATAPATH = REPOPATH and os.path.join(REPOPATH, DATANAME)
THUMBSPATH = REPOPATH and os.path.join(REPOPATH, THUMBSNAME)

class Handler(SimpleHTTPServer.SimpleHTTPRequestHandler):
    
    def do_GET(self):
        link = self.path[1:]
        top = os.path.join(REPOROOT, link)
        if os.path.isfile(top):
            self.serve_file(top)
        else:
            self.serve_dir(top)

    def serve_dir(self, top):
        data = Database()
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write("""
        <style>
            * {
                font-family: sans-serif;
                font-size: 8pt;
            }
            div { display: inline-block; }
        </style>
        """)
        for dirpath, dirnames, filenames in walk(top):
            for thisname in dirnames + filenames:
                thispath = os.path.join(dirpath, thisname)
                thislink = getlink(thispath)
                filedata = data.get_files(thislink).fetchone()
                if os.path.isdir(thispath):
                    del dirnames[dirnames.index(thisname)]
                if filedata is not None:
                    filelink, filehash = filedata
                    thumbpath = get_thumbpath(filehash)
                    if os.path.exists(thumbpath):
                        tags = data.get_tags_for_file(thispath)
                        print [tag for tag in tags]
                        thumblink = getlink(thumbpath)
                        self.wfile.write('<div><a href="/%s"><img src="/%s"/></a><br/>%s</div>' % (thislink, thumblink, thisname))
                    else:
                        self.wfile.write('<div><a href="/%s">%s</a></div>' % (thislink, thisname))

    def serve_file(self, top):
        ext = os.path.splitext(top)[-1][1:]
        self.send_response(200)
        self.send_header('Content-type', 'image/%s' % (ext))
        self.end_headers()
        with open(top, 'rb') as f:
            self.wfile.write(f.read())

lock = threading.Lock()

def create_thumbnail(filepath, thumbpath, size=(200, 200)):
    try:
        im = Image.open(filepath)
        w, h = im.size
        if w < h:
            left = 0
            upper = 0
            right = w
            lower = w
        else:
            left = (w-h)/2
            upper = 0
            right = h + left
            lower = h
        box = (left, upper, right, lower)
        im = im.crop(box)
        im.thumbnail(size, Image.ANTIALIAS)
        im.save(thumbpath)
        return True
    except IOError:
        return False

def gethash(filepath):
    with open(filepath, 'rb') as f:
        return hashlib.md5(f.read()).hexdigest()

def getlink(filepath):
    return os.path.relpath(filepath, REPOROOT)

def getlike(filepath):
    filelink = getlink(filepath)
    if os.path.isfile(filepath):
        return filelink
    if filelink == '.':
        return '%'
    return os.path.join(filelink, '%')

def get_thumbpath(filehash):
    return os.path.join(THUMBSPATH, '%s.jpg' % (filehash))

class Database:

    SQL_TABLES = [
        'CREATE TABLE data (hash TEXT PRIMARY KEY, size INTEGER)',
        'CREATE TABLE links (link TEXT PRIMARY KEY, hash TEXT)',
        'CREATE TABLE tags (id INTEGER PRIMARY KEY, name TEXT UNIQUE)',
        'CREATE TABLE taglinks (tag INTEGER, hash TEXT)',
    ]

    def __init__(self):
        exists = os.path.exists(DATAPATH)
        self.__connection = sqlite3.connect(DATAPATH)
        self.__cursor = self.__connection.cursor()
        if not exists:
            for sql in self.SQL_TABLES:
                self.__execute(sql)

    def __commit(self):
        self.__connection.commit()

    def __cursor__(self):
        return self.__connection.cursor()

    def __execute(self, *args, **kwargs):
        return self.__cursor.execute(*args, **kwargs)

    def add_file(self, filepath):
        filehash = gethash(filepath)
        filelink = getlink(filepath)
        self.__execute('INSERT INTO links (link, hash) VALUES (?, ?);',
                           (filelink, filehash))

    def add_tag(self, tagname):
        self.__execute('INSERT INTO tags (name) VALUES (?)', (tagname,))

    def add_taglink(self, tagid, filehash):
        self.__execute('INSERT INTO taglinks (tag, hash) VALUES (?, ?)', (tagid, filehash))

    def get_file(self, filepath):
        filelink = getlink(filepath)
        return self.__execute('SELECT * FROM links WHERE link = ?', (filelink,)).fetchone()

    def get_files(self, filepath='.'):
        filelike = getlike(filepath)
        return self.__execute('SELECT * FROM links WHERE link LIKE ?;', (filelike,))

    def get_files_with_tags(self, filepath):
        filelike = getlike(filepath)
        return self.__execute('SELECT links.link, tags.name '
                              'FROM links JOIN tags JOIN taglinks '
                              'WHERE links.link LIKE ? '
                              'AND links.hash = taglinks.hash '
                              'AND tags.id = taglinks.tag',
                              (filelike,))

    def get_tag(self, tagname):
        return self.__execute('SELECT * FROM tags WHERE name = ?', (tagname,)).fetchone()

    def get_taglink(self, tagid, filehash):
        return self.__execute('SELECT * FROM taglinks WHERE tag = ? AND hash = ?', (tagid, filehash)).fetchone()

    def __get_or_add(self, get, add, *args, **kwargs):
        result, added = get(*args, **kwargs), False
        if result is None:
            add(*args, **kwargs)
            self.__commit()
            result, added = get(*args, **kwargs), True
        return result, added

    def get_or_add_file(self, filepath):
        return self.__get_or_add(self.get_file, self.add_file, filepath)

    def get_or_add_tag(self, tagname):
        return self.__get_or_add(self.get_tag, self.add_tag, tagname)

    def get_or_add_taglink(self, tagid, filehash):
        return self.__get_or_add(self.get_taglink, self.add_taglink, tagid, filehash)

    def get_tags_for_file(self, filepath):
        filelike = getlike(filepath)
        return self.__execute('SELECT tags.name FROM tags JOIN taglinks JOIN links WHERE tags.id = taglinks.tag AND taglinks.hash = links.hash AND links.link LIKE ?',
                             (filelike,))

def walk(top):
    for dirpath, dirnames, filenames in os.walk(top):
        for filename in IGNORE_FILENAMES:
            if filename in dirnames:
                del dirnames[dirnames.index(filename)]
            if filename in filenames:
                del filenames[filenames.index(filename)]
        yield dirpath, dirnames, filenames

### COMMANDS

def add_command(args):
    data = Database()
    for top in args.files:
        if os.path.isfile(top):
            row, added = data.get_or_add_file(top)
            if args.v and added:
                print 'added', top
        else:
            for dirpath, dirnames, filenames in walk(top):
                for filename in filenames:
                    name, ext = os.path.splitext(filename)
                    if args.e and args.e != ext:
                        continue
                    filepath = os.path.join(dirpath, filename)
                    row, added = data.get_or_add_file(filepath)
                    if args.v and added:
                        print 'added', filepath

def html_command(args):
    data = Database()
    htmlpath = os.path.join(REPOPATH, 'index.html')
    with open(htmlpath, 'w') as f:
        for filelink, filehash in data.get_files(REPOROOT):
            filepath = os.path.join(REPOROOT, filelink)
            thumbpath = get_thumbpath(filehash)
            f.write('<a href="%s"><img src="%s"/></a>' % (filepath, thumbpath))

def init_command(args):
    global REPOPATH
    if REPOPATH is None:
        REPOPATH = os.path.join(os.path.abspath('.'), REPONAME)
        print 'initializing tag repo at %s' % (REPOPATH)
        os.mkdir(REPOPATH)
    else:
        print 'repo already exists at %s' % (REPOPATH)

def list_command(args):
    data = Database()
    tags_by_file = defaultdict(list)
    for top in args.files:
        for filelink, tagname in data.get_files_with_tags(top):
            tags_by_file[filelink].append(tagname)
    for filelink in sorted(tags_by_file):
        tags = tags_by_file[filelink]
        if not args.t or all(tag in tags for tag in args.t):
            print '%s: %s' % (filelink, ', '.join(sorted(tags)))

def server_command(args):
    import SocketServer
    server_address = ('', args.p)
    httpd = SocketServer.TCPServer(server_address, Handler)
    try:
        print 'serving at port %d' % (args.p)
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass

def status_command(args):
    data = Database()
    for dirpath, dirnames, filenames in walk(REPOROOT):
        for dirname in dirnames[:]:
            dirpath_ = os.path.join(dirpath, dirname)
            if data.get_files(dirpath_).fetchone() is None:
                print 'unstaged: %s%s' % (os.path.relpath(dirpath_, '.'), os.sep)
                del dirnames[dirnames.index(dirname)]
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            if not data.get_file(filepath):
                print 'unstaged: %s' % (os.path.relpath(filepath, '.'))

def tag_command(args):
    data = Database()
    for tagname in args.t:
        (tagid, tagname), added = data.get_or_add_tag(tagname)
        if args.v and added:
            print 'added tag: %s' % (tagname)
        for top in args.files:
            for filelink, filehash in list(data.get_files(top)):
                got, added = data.get_or_add_taglink(tagid, filehash)
                if added and args.v:
                    print 'applied tag "%s" to "%s"' % (tagname, filelink)

def thumbs_command(args):
    class Thread(threading.Thread):
        def __init__(self, filelink, thumbpath):
            threading.Thread.__init__(self)
            self.filelink = filelink
            self.thumbpath = thumbpath
        def run(self):
            filepath = os.path.join(REPOROOT, self.filelink)
            created = create_thumbnail(filepath, self.thumbpath)
            if args.v:
                with lock:
                    if created:
                        print 'creating thumbnail for %s' % (self.filelink)
                    else:
                        print 'could not create thumbnail for %s' % (self.filelink)
    if not os.path.exists(THUMBSPATH):
        os.mkdir(THUMBSPATH)
    data = Database()
    threads = []
    for top in args.files:
        for filelink, filehash in data.get_files(top):
            thumbpath = get_thumbpath(filehash)
            if not os.path.exists(thumbpath):
                thread = Thread(filelink, thumbpath)
                thread.start()
                threads.append(thread)
    for thread in threads:
        thread.join()

def test(args):
    data = Database()
    path = os.path.abspath('testdir')
    print [tag for tag in data.get_tags_for_file(path)]

### MAIN

def main(args):
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers()
    # add
    subparser = subparsers.add_parser('add')
    subparser.set_defaults(func=add_command)
    subparser.add_argument('-e', metavar='ext')
    subparser.add_argument('-v', action='store_true')
    subparser.add_argument('files', nargs='+')
    # html
    subparser = subparsers.add_parser('html')
    subparser.set_defaults(func=html_command)
    # init
    subparser = subparsers.add_parser('init')
    subparser.set_defaults(func=init_command)
    subparser.add_argument('directory', default='.', nargs='?')
    # list
    subparser = subparsers.add_parser('list')
    subparser.set_defaults(func=list_command)
    subparser.add_argument('-t', action='append', metavar='tag', help='tag to list')
    subparser.add_argument('files', default=['.'], nargs='*')
    # server
    subparser = subparsers.add_parser('server')
    subparser.set_defaults(func=server_command)
    subparser.add_argument('-p', default=8000, metavar='port', type=int)
    # status
    subparser = subparsers.add_parser('status')
    subparser.set_defaults(func=status_command)
    # tag
    subparser = subparsers.add_parser('tag')
    subparser.set_defaults(func=tag_command)
    subparser.add_argument('-v', action='store_true')
    subparser.add_argument('-t', action='append', metavar='tag', help='tag to apply')
    subparser.add_argument('files', nargs='+', help='files to tag')
    # thumbs
    subparser = subparsers.add_parser('thumbs')
    subparser.set_defaults(func=thumbs_command)
    subparser.add_argument('-v', action='store_true')
    subparser.add_argument('files', default=['.'], nargs='*')
    # ...
    subparser = subparsers.add_parser('test')
    subparser.set_defaults(func=test)
    args = parser.parse_args(args)
    args.func(args)

if __name__ == '__main__':
    main(sys.argv[1:])
