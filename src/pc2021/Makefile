# Matt Champlin 
# Date: Sat Jan 30 02:13:27 EST 2021
# Makefile Template
#


CXX      = clang++
CXXFLAGS = -g3 -Wall -Wextra


hello: helloworld.cpp
		${CXX} ${CXXFLAGS} -o $@ $^
	
%.o: %.cpp $(shell echo *.h)
	${CXX} ${CXXFLAGS} -c $<

