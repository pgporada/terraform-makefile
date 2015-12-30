# terraform-stuff

## Basic Usage
### First steps
View contents of the Makefile
```
ENVIRONMENT=qa make
```

### Planning
Show a plan from the remote state
```
ENVIRONMENT=qa make plan
```

### Outputs
Show root level output
```
ENVIRONMENT=qa make output
```

Output a module
```
MODULE=network ENVIRONMENT=qa make output
```

Output a nested module
```
MODULE=network.nat ENVIRONMENT=qa make output
```
