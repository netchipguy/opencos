
# SPDX-License-Identifier: MPL-2.0

import sys
import subprocess

args = {
    'color' : True,
    'quiet' : False,
    'verbose' : False,
    'debug' : False,
    'warnings' : 0,
    'errors' : 0,
}

def process_token(arg):
    if arg == '--color': args['color'] = True
    elif arg == '--no-color': args['color'] = False
    elif arg == '--quiet': args['quiet'] = True
    elif arg == '--no-quiet': args['quiet'] = False
    elif arg == '--verbose': args['verbose'] = True
    elif arg == '--no-verbose': args['verbose'] = False
    elif arg == '--debug': args['debug'] = True
    elif arg == '--no-debug': args['debug'] = False
    else: return False
    debug(f"Processed command: {arg}")
    return True

def print_red(text):
    print(f"\x1B[31m{text}\x1B[0m" if args['color'] else f"{text}")

def print_green(text):
    print(f"\x1B[32m{text}\x1B[0m" if args['color'] else f"{text}")

def print_orange(text):
    print(f"\x1B[33m{text}\x1B[0m" if args['color'] else f"{text}")

def print_yellow(text):
    print(f"\x1B[39m{text}\x1B[0m" if args['color'] else f"{text}")

def debug(text, level=1):
    if args['debug'] and ((level==1) or args['verbose']):
        print_yellow(f"DEBUG: [EDA] {text}")

def info(text):
    if not args['quiet']:
        print_green(f"INFO: [EDA] {text}")

def warning(text):
    args['warnings'] += 1
    print_orange(f"WARNING: [EDA] {text}")

def error(text, error_code=-1, do_exit=True):
    args['errors'] += 1
    print_red(f"ERROR: [EDA] {text}")
    if do_exit: exit(error_code)

def exit(error_code=0):
    info(f"Exiting with {args['warnings']} warnings, {args['errors']} errors")
    sys.exit(error_code)

def get_oc_root():
    cp = subprocess.run('git rev-parse --show-toplevel', stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        shell=True, universal_newlines=True)
    if cp.returncode != 0:
        return False
    return cp.stdout.strip()
