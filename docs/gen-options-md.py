#!/usr/bin/env python3

import json
import sys

def main():
    docs = json.load(open(sys.argv[1]))

    for option, attrs in docs.items():
        print(f"""\
- {option}
   description: {attrs.get('description', '')}
   default: {attrs.get('default', '')}
   type: {attrs.get('type', '')}
""")

if __name__ == '__main__':
    main()
