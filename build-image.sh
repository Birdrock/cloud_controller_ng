#! /bin/sh

BASEDIR=$(dirname $0)

case $# in
	0) docker build --build-arg GIT_REV=$(git rev-parse HEAD) -t awittrock/test-ccng $BASEDIR  ;;
	*) docker build --build-arg BUILD_IMAGE=$1 --build-arg GIT_REV=$(git rev-parse HEAD) -t awittrock/test-ccng $BASEDIR ;;
esac
