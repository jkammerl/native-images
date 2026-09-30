"""IPython kernel configuration for the code execution Jupyter server."""

c = get_config()

# By default, IPython captures low-level file descriptor output (fd 1 / fd 2)
# and forwards it over the IOPub WebSocket channel so users see stdout from C
# extensions that bypass sys.stdout.
#
# We disable this capture mechanism so that our raw internal logger (which
# writes to sys.__stdout__) emits messages exclusively to the Jupyter
# container's log stream without polluting the user's execution response stream.
c.IPKernelApp.capture_fd_output = False
