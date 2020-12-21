# Intro

An ansible inventory plugin for rancher server. Deploy to your clusters as hosts.

# Commands

```sh
# if you need to cleanup first a previous installation
# make destroy
# check requirements
make prep
# create infrastructure
make create
# ansible image
make build
# print inventory graph
make graph
# deploy demo using ansible playbook
make play
# check via browser: http://localhost:808{0,1,3} or execute (might have to wait for deployment to complete):
make test
```

Inventory plugin in action.

```sh
$ make graph
@all:
  |--@aws:
  |  |--demo2
  |  |--demo3
  |--@azure:
  |  |--demo1
  |--@production:
  |  |--demo3
  |--@staging:
  |  |--demo1
  |  |--demo2
  |--@ungrouped:
```

More info in the role [README](roles/helm_deploy/README.md).


# Development


```sh
make lint
```
