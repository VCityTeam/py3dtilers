debug_mode = True


def debug_msg(message):
    if debug_mode:
        print(message, flush=True)


def debug_msg_ne(message):
    """
    nr stands for No Endline
    """
    if debug_mode:
        print(message, end='\r', flush=True)
