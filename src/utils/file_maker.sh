#!/bin/bash


# Usage: ./file_maker.sh [class|cpp] [classname|filename]
#        ./file_maker.sh make executable dependnecy1 dependency2 ...
#        if you do ./file_maker class my_class, the y tells this to make a class
#        if you do ./filemaker cpp my_file.cpp, the n tells this to make a .cpp file
#        if you do ./filemaker make my_executable my_dependency1.cpp dependency2.cpp
#           will make a Makefile that will compile my_executable
# This program writes dummy classes and .cpp files for using with 
# provide_checker.sh.  

FILE_TYPE=$1
FILENAME=$2

# function : classmaker()
# args: FILENAME - the name of the class. In other words, we make a .cpp
#                  and .h using this filename
# does:  Makes a "working" class using the user specified filename.  This is
#        only run if the user runs with ./file_maker.sh class classname
function classmaker() {
    
EXTENSION=".cpp"

DATE=$(date)

cat >> "$FILENAME$EXTENSION" << EOF
/******************************************************************************
*   Program:    $FILENAME$EXTENSION
*   Created By: Matt Champlin
*   Date:       $DATE
*               
*   Program Purpose: Dummy $FILENAME$EXTENSION file for provide checker
*                    
******************************************************************************/

#include <iostream>



int main() 
{
    std::cout << "Hello World!" << std::endl;
    return 0;
}

EOF


EXTENSION=.h


cat >> "$FILENAME$EXTENSION" << EOF
/******************************************************************************
*   Program:    $FILENAME$EXTENSION
*   Created By: Matt Champlin
*   Date:       $DATE
*               
*   Program Purpose: Dummy $FILENAME$EXTENSION for providechecker utility
*                    
******************************************************************************/

#ifndef _${FILENAME^^}_H_
#define _${FILENAME^^}_H_

#include <iostream>

class $FILENAME {
    public:
        $FILENAME();
        ~$FILENAME();
    private:
        std::string greeting;
};
    
#endif
EOF
}


# function : cpp_maker()
# args: FILENAME - the name of the .cpp file you want made
# does:  Makes a working .cpp using the user specified filename. This is
#        only run if the user runs this script with ./file_maker.sh cpp filename
function cpp_maker() {

touch "$FILENAME"
DATE=$(date)
cat >> "$FILENAME" << EOF
/******************************************************************************
*   Program:    $FILENAME
*   Created By: Matt Champlin
*   Date:       $DATE
*               
*   Program Purpose: Dummy $FILENAME file for provide checker
*                    
******************************************************************************/

#include <iostream>


int main() {

    std::cout << "Hello World!" << std::endl;

    return 0;
}

EOF
}

function make_maker() {

# create variables for name of executable, date etc...
MAKEFILE="Makefile"
shift
EXEC="$1"
shift


DATE=$(date)

# print the following into the file. 
cat >> "$MAKEFILE" << EOF
# Matt Champlin 
# Date: $DATE
# Makefile Template
#


CXX      = clang++
CXXFLAGS = -g3 -Wall -Wextra


$EXEC: $@
		\${CXX} \${CXXFLAGS} -o \$@ $^
	
%.o: %.cpp \$(shell echo *.h)
	\${CXX} \${CXXFLAGS} -c $<

EOF
}


## Run the program ##

if [[ "$FILE_TYPE" == "class" ]]; then
        classmaker 
elif [[ "$FILE_TYPE" == "make" ]]; then
        make_maker $@
elif [[ "$FILE_TYPE" == "cpp" ]]; then
        cpp_maker 
else
        echo "Usage: ./file_maker.sh [class|cpp] [classname|filename]"
        echo "   OR: ./file_maker.sh make executable dependnecy1 dependency2 ..."
fi




