
# SPDX-License-Identifier: MPL-2.0

import sys
import subprocess
import datetime
import os
import time
import atexit
import shutil

progname = "UNKNOWN"
progname_in_message = True
logfile = None
loglast = 0
debug_level = 0

args = {
    'color' : True,
    'quiet' : False,
    'verbose' : False,
    'debug' : False,
    'fancy' : sys.stdout.isatty(),
    'warnings' : 0,
    'errors' : 0,
}

def start_log(filename, force=False):
    global logfile, loglast
    if os.path.exists(filename):
        if force:
            info(f"Overwriting '{filename}', which exists, due to --force-logfile.")
        else:
            error(f"The --logfile path '{filename}' exists.  Use --force-logfile (vs --logfile) to override.")
    try:
        logfile = open( filename, 'w')
        debug(f"Opened logfile '{filename}' for writing")
    except Exception as e:
        error(f"Error opening '{filename}' for writing!")

def write_log(text, end):
    global logfile, loglast
    sw = text.startswith(f"INFO: [{progname}]")
    if (((time.time() - loglast) > 10) and
        (text.startswith(f"DEBUG: [{progname}]") or
         text.startswith(f"INFO: [{progname}]") or
         text.startswith(f"WARNING: [{progname}]") or
         text.startswith(f"ERROR: [{progname}]"))):
        dt = datetime.datetime.now().ctime()
        print(f"INFO: [{progname}] Time: {dt}", file=logfile)
        loglast = time.time()
    print(text, end=end, file=logfile)
    logfile.flush()
    os.fsync(logfile)

def stop_log():
    global logfile, loglast
    if logfile:
        debug(f"Closing logfile")
        logfile.close()
    logfile = None
    loglast = 0

atexit.register(stop_log)

# this ugliness is because we just call util.process_token once with each token, it was
# setup to "steal" --<flag> looking options.  For this reason, we also don't have the
# benefit of everything being ingested before processing starts (i.e. what enables
# --debug to be added at the end, and still enable debug for the 'eda sim').  If we
# had a --force option below, it would run "in order" without a bit of mess here, so
# instead there's just a --force-logfile version of the --logfile option...
logfile_is_next_arg = False
logfile_is_forced = False

def process_token(arg):
    global logfile_is_next_arg
    global logfile_is_forced
    if logfile_is_next_arg:
        start_log(arg, force=logfile_is_forced)
        logfile_is_next_arg = False
    elif arg == '--color': args['color'] = True
    elif arg == '--no-color': args['color'] = False
    elif arg == '--quiet': args['quiet'] = True
    elif arg == '--no-quiet': args['quiet'] = False
    elif arg == '--verbose': args['verbose'] = True
    elif arg == '--no-verbose': args['verbose'] = False
    elif arg == '--fancy': args['fancy'] = True
    elif arg == '--no-fancy': args['fancy'] = False
    elif arg == '--debug':
        args['debug'] = True
        debug_level += 1
    elif arg == '--no-debug':
        args['debug'] = False
        debug_level = 0
    elif arg == '--logfile':
        logfile_is_next_arg = True
    elif arg == '--force-logfile':
        logfile_is_next_arg = True
        logfile_is_forced = True
    else:
        return False
    debug(f"Processed command: {arg}")
    return True

# ********************
# fancy support
# In fancy mode, we take the bottom fancy_lines_ lines of the screen to be written using fancy_print,
# while the lines above that show regular scrolling content (via info, debug, warning, error above).
# User should not use print() when in fancy mode

fancy_lines_ = []

def fancy_start(fancy_lines = 4, min_vanilla_lines = 4):
    global fancy_lines_
    (columns,lines) = shutil.get_terminal_size()
    if (fancy_lines < 2):
        error(f"Fancy mode requires at least 2 fancy lines")
    if (fancy_lines > (lines-min_vanilla_lines)):
        error(f"Fancy mode supports at most {(lines-min_vanilla_lines)} fancy lines, given {min_vanilla_lines} non-fancy lines")
    if len(fancy_lines_): error(f"We are already in fancy line mode??")
    for _ in range(fancy_lines-1):
        print("") # create the requisite number of blank lines
        fancy_lines_.append("")
    print("", end="") # the last line has no "\n" because we don't want ANOTHER blank line below
    fancy_lines_.append("")
    # the cursor remains at the leftmost character of the bottom line of the screen

def fancy_stop():
    global fancy_lines_
    if len(fancy_lines_): # don't do anything if we aren't in fancy mode
        # user is expected to have painted something into the fancy lines, we can't "pull down" the regular
        # lines above, and we don't want fancy_lines_ blank or garbage lines either, that's not pretty
        fancy_lines_ = []
        # since cursor is always left at the leftmost character of the bottom line of the screen, which was
        # one of the fancy lines which now has the above-mentioned "something", we want to move one lower
        print("")

def fancy_print(text, line):
    global fancy_lines_
    # strip any newline, we don't want to print that
    if text.endswith("\n"): text.rstrip()
    lines_above = len(fancy_lines_) - line - 1
    if lines_above:
        print(f"\033[{lines_above}A"+ # move cursor up
              text+f"\033[1G"+ # desired text, then move cursor to the first character of the line
              f"\033[{lines_above}B", # move the cursor down
              end="", flush=True)
    else:
        print(text+f"\033[1G", # desired text, then move cursor to the first character of the line
              end="", flush=True)
    fancy_lines_[line] = text

def print_pre():
    # stuff we do before printing any line
    if len(fancy_lines_):
        # Also, note that in fancy mode we don't allow the "above lines" to be partially written, they
        # are assumed to be full lines ending in "\n"
        # As always, we expect the cursor was left in the leftmost character of bottom line of screen
        print(f"\033[{len(fancy_lines_)-1}A"+ # move the cursor up to where the first fancy line is drawn
              f"\033[0K", # clear the old fancy line 0
              end="",flush=True)

def print_post(text, end):
    # stuff we do after printing any line
    if len(fancy_lines_):
        #time.sleep(1)
        # we just printed a line, including a new line, on top of where fancy line 0 used to be, so cursor
        # is now at the start of fancy line 1.
        # move cursor down to the beginning of the final fancy line (i.e. standard fancy cursor resting place)
        for x in range(len(fancy_lines_)):
            print("\033[0K",end="") # erase the line to the right
            print(fancy_lines_[x],flush=True,end=('' if x==(len(fancy_lines_)-1) else '\n'))
            #time.sleep(1)
        print("\033[1G", end="", flush=True)
    if logfile: write_log(text, end=end)

string_red = f"\x1B[31m"
string_green = f"\x1B[32m"
string_orange = f"\x1B[33m"
string_yellow = f"\x1B[39m"
string_normal = f"\x1B[0m"

def print_red(text, end='\n'):
    print_pre()
    print(f"{string_red}{text}{string_normal}" if args['color'] else f"{text}", end=end, flush=True)
    print_post(text, end)

def print_green(text, end='\n'):
    print_pre()
    print(f"{string_green}{text}{string_normal}" if args['color'] else f"{text}", end=end, flush=True)
    print_post(text, end)

def print_orange(text, end='\n'):
    print_pre()
    print(f"{string_orange}{text}{string_normal}" if args['color'] else f"{text}", end=end, flush=True)
    print_post(text, end)

def print_yellow(text, end='\n'):
    print_pre()
    print(f"{string_yellow}{text}{string_normal}" if args['color'] else f"{text}", end=end, flush=True)
    print_post(text, end)

def set_debug_level(level):
    debug_level = level
    args['debug'] = (level > 0)
    args['verbose'] = (level > 1)

# the <<d>> stuff is because we change progname after this is read in.  if we instead infer progname or
# get it passed somehow, we can avoid this ugliness / performance impact (lots of calls to debug happen)
def debug(text, level=1, start='<<d>>', end='\n'):
    if start=='<<d>>': start = f"DEBUG: " + (f"[{progname}] " if progname_in_message else "")
    if args['debug'] and ((level==1) or args['verbose'] or (debug_level >= level)):
        print_yellow(f"{start}{text}", end=end)

def info(text, start='<<d>>', end='\n'):
    if start=='<<d>>': start = f"INFO: " + (f"[{progname}] " if progname_in_message else "")
    if not args['quiet']:
        print_green(f"{start}{text}", end=end)

def warning(text, start='<<d>>', end='\n'):
    if start=='<<d>>': start = f"WARNING: " + (f"[{progname}] " if progname_in_message else "")
    args['warnings'] += 1
    print_orange(f"{start}{text}", end=end)

def error(text, error_code=-1, do_exit=True, start='<<d>>', end='\n'):
    if start=='<<d>>': start = f"ERROR: " + (f"[{progname}] " if progname_in_message else "")
    args['errors'] += 1
    print_red(f"{start}{text}", end=end)
    if do_exit: exit(error_code)

def exit(error_code=0):
    info(f"Exiting with {args['warnings']} warnings, {args['errors']} errors")
    sys.exit(error_code)

def getcwd():
    try:
        cc = os.getcwd()
    except Exception as e:
        error("Unable to getcwd(), did it get deleted from under us?")
    return cc

def get_oc_root():
    cp = subprocess.run('git rev-parse --show-toplevel', stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        shell=True, universal_newlines=True)
    if cp.returncode != 0:
        return False
    return cp.stdout.strip()

def string_or_space(text, whitespace=False):
    if whitespace:
        return " " * len(text)
    else:
        return text

def sprint_time(s):
    s = int(s)
    txt = ""
    do_all = False
    # days
    if (s >= (24*60*60)): # greater than 24h, we show days
        d = int(s/(24*60*60))
        txt += f"{d}d:"
        s -= (d*24*60*60)
        do_all = True
    # hours
    if do_all or (s >= (60*60)):
        d = int(s/(60*60))
        txt += f"{d:2}:"
        s -= (d*60*60)
        do_all = True
    # minutes
    d = int(s/(60))
    txt += f"{d:02}:"
    s -= (d*60)
    # seconds
    txt += f"{s:02}"
    return txt
