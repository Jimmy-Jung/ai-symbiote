[Seed #S1] Always use virtual environment paths; never install packages globally via pip
[Seed #S2] When adding new dependencies, update requirements.txt or pyproject.toml immediately
[Seed #S3] Use type hints for function signatures; do not leave parameters untyped in new code
[Seed #S4] Never catch bare Exception; catch specific exception types to avoid masking bugs
[Seed #S5] When modifying database models (SQLAlchemy, Django), always create a migration file
[Seed #S6] Use pathlib.Path instead of os.path.join for file path operations
[Seed #S7] Do not use mutable default arguments (def f(x=[])); use None with conditional initialization
[Seed #S8] When adding async code, verify the event loop is not blocked by synchronous I/O calls
