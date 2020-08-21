#!/bin/bash

# Usage: ./provide_checker.sh homework_name file1 file2 file3 ...

# Validates user has properly run program
function validate_usage() 
{
    # Check to make sure user has run the program correctly
    if [[ "$#" -lt 2 ]]; then
        echo "Invalid number of arguments provided"
        echo "Usage: $0 homework_name file1 file2 file3 ..."
        exit
    fi
}

# removes line continuations from a given file
function remove_line_continuations() 
{
    parsed=$(sed -e ':x /[[:space:]]*\\$/ { N; s/[[:space:]]*\\\n//g; s/[[:space:]][[:space:]]*/ /g ; bx }' "$1")
    echo "$parsed"
}

# Sets variables we need for various purposes. Takes all arguments from 
# command line
function set_variables() 
{
    # Store homework name, user given files and set up file paths
    REMOTE="mkorma01@homework.cs.tufts.edu"
    HWNAME="$1"
    shift
    USR_FILES=("$@")
    TEST_SET_PATH=/comp/15/grading/screening/testsets/"$HWNAME"
    ASSN_CONF=/comp/15/grading/assignments.conf
    PC_TEST_DIR=${BASH_SOURCE%/*}/checkers
    TEST_DIR="$HWNAME"_pc_submission
    mkdir "$TEST_DIR"

    # Remove line continuations and store testset
    TEST_SET=$(remove_line_continuations "$TEST_SET_PATH")
}

# Requires filepath of directory 
# Directory will be created and have user files copied into
function copy_files() 
{
    mkdir "$1"
    for file in "${USR_FILES[@]}"; do
        if ! cp "$file" "$1"; then
            echo "Files don't exist in this directory or are spelled wrong!"
            rm -r "$1"
            exit 1
        fi
    done
}

# Takes all arguments passed in from command line
function setup() {
    set_variables "$@"
    copy_files "$TEST_DIR/passing"
    # copy files to student level account
    scp -q -r "$TEST_DIR" "$REMOTE":~/ProvideCheck
}

# Asserts that the assignment has been added to assignments.conf 
# and is uncommented
function validate_assignment() 
{ 
    if ! ASSIGN=$(remove_line_continuations "$ASSN_CONF" | grep '^[^#][a-z]*='"$HWNAME"'\s'); then
        echo "Assignment doesn't exist in $ASSN_CONF or is commented out."
        echo "Please add the assignment to assignments.conf and try again."
        exit 1
    fi
}

# Checks pc_test directory for the test name passed in as an argument
function check_for_test() 
{
    if [ -f "$PC_TEST_DIR/$1" ]; then
        return 0
    else
        return 1
    fi
}   

# Takes exit status of a given test and determines success or failure
function assert_test()
{
    # echo "exit status: $1"
    if [[ "$1" == 1 ]]; then
        echo "~~~~~~~ $2 test failed. ~~~~~~~"
        echo ""
    else
        echo "~~~~~~~ $2 test passed. ~~~~~~~"
        echo ""
    fi
}

# Runs tests.  Passing test always runs.  Other tests are parsed from the 
# testset and run if they are found.
function run_tests() 
{
    # we always run passing test
    ssh "$REMOTE" 'bash -s' < $PC_TEST_DIR/passing "$HWNAME" "$TEST_DIR/passing" 
    assert_test "$?" passing

    # Next we parse the TEST_SET for tests, and execute them if they exist
    echo "$TEST_SET" | while read line ; do   
        if TEST_LINE=($(egrep '^(FAIL|WARN)' <<< "$line")); then
            POSSIBLE_TEST="${TEST_LINE[1]}"
            if check_for_test "$POSSIBLE_TEST"; then # if test exists
                copy_files "$TEST_DIR/$POSSIBLE_TEST"
                # run test
                $PC_TEST_DIR/$POSSIBLE_TEST "$HWNAME" "$TEST_DIR" \
                "$TEST_DIR/$POSSIBLE_TEST" "$REMOTE" ${TEST_LINE[@]}
                assert_test "$?" "$POSSIBLE_TEST"
            fi
        fi
    done
}




# Lets run it!

validate_usage "$@"
setup "$@"
validate_assignment
run_tests

rm -rf $TEST_DIR





