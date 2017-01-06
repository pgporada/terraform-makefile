# Usage
View help/description of Makefile goals

    make

Show a plan from the remote state

    ENVIRONMENT=qa make plan

Show root level output

    ENVIRONMENT=qa make output

Output a module

    MODULE=network ENVIRONMENT=qa make output

Output a nested module

    MODULE=network.nat ENVIRONMENT=qa make output

- - - -
# Author Info
(C) [Phil Porada](https://github.com/pgporada/) - philporada@gmail.com
