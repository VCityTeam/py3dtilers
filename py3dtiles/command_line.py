import argparse
import py3dtiles.convert as convert
import py3dtiles.info as info
import py3dtiles.merger as merger
import py3dtiles.export as export
import traceback

# https://stackoverflow.com/a/43357954
def str2bool(v):
    if v.lower() in ('yes', 'true', 't', 'y', '1'):
        return True
    elif v.lower() in ('no', 'false', 'f', 'n', '0'):
        return False
    else:
        raise argparse.ArgumentTypeError('Boolean value expected.')


def main():
    parser = argparse.ArgumentParser(
        description='Read/write 3dtiles files',
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument(
        '--verbose',
        help='Print logs (-1: no logs, 0: progress indicator, 1+: increased verbosity)',
        default=0, type=int)
    sub_parsers = parser.add_subparsers(dest='command')

    # init subparsers
    convert.init_parser(sub_parsers, str2bool)
    info.init_parser(sub_parsers, str2bool)
    merger.init_parser(sub_parsers, str2bool)
    export.init_parser(sub_parsers, str2bool)

    args = parser.parse_args()

    try:
        if args.command == 'convert':
            convert.main(args)
        elif args.command == 'info':
            info.main(args)
        elif args.command == 'merge':
            merger.main(args)
        elif args.command == 'export':
            export.main(args)
        else:
            parser.print_help()
    except Exception as e:
        traceback.print_exc()
        print('')
        parser.print_help()

if __name__ == '__main__':
    main()
