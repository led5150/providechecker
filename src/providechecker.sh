#!/bin/bash

# Validates user has properly run program
function validate_usage() {
        # Check to make sure user has run the program correctly
        if [[ "$#" -lt 2 ]]; then
                echo "Invalid number of arguments provided"
                echo "Usage: $0 homework_name file1 file2 file3 ..."
                exit
        fi
}

# removes line continuations from a given file
function remove_line_continuations() {
        parsed=$(sed -e ':x /[[:space:]]*\\$/ { N; s/[[:space:]]*\\\n//g; s/[[:space:]][[:space:]]*/ /g ; bx }' "$1")
        echo "$parsed"
}

# Sets variables we need for various purposes. Takes all arguments from
# command line
function set_variables() {
        # Store homework name, user given files and set up file paths
        REMOTE="mkorma01@homework.cs.tufts.edu"
        HWNAME="$1"
        shift
        USR_FILES=("$@")
        TEST_SET_PATH=/comp/15/grading/screening/testsets/"$HWNAME"
        ASSN_CONF=/comp/15/grading/assignments.conf
        CHECKERS=${BASH_SOURCE%/*}/checkers
        BASE_DIR="providecheck/$HWNAME"
        mkdir -p "$BASE_DIR"

        # Remove line continuations and store testset
        TEST_SET=$(remove_line_continuations "$TEST_SET_PATH")
}

# Requires filepath of directory
# Directory will be created and have user files copied into
function copy_files() {
        mkdir -p "$1"
        cp "${USR_FILES[@]}" "$1"

        # for file in "${USR_FILES[@]}"; do
        #         if ! cp "$file" "$1"; then
        #                 echo "Files don't exist in this directory or are spelled wrong!"
        #                 rm -r "$1"
        #                 exit 1
        #         fi
        # done
}

# Takes all arguments passed in from command line
function setup() {
        set_variables "$@"
}

# Asserts that the assignment has been added to assignments.conf
# and is uncommented
function validate_assignment() {
        if ! ASSIGN=$(remove_line_continuations "$ASSN_CONF" | grep '^[^#][a-z]*='"$HWNAME"'\s'); then
                echo "Assignment doesn't exist in $ASSN_CONF or is commented out."
                echo "Please add the assignment to assignments.conf and try again."
                exit 1
        fi
}

# Takes exit status of a given test and determines success or failure
function assert_test() {
        # echo "exit status: $1"
        if [[ "$1" == 1 ]]; then
                echo "~~~~~~~ $2 test failed. ~~~~~~~"
                echo ""
        else
                echo "~~~~~~~ $2 test passed. ~~~~~~~"
                echo ""
        fi
}

function perform_edits() {
        i=1
        mapfile -t LINES <<<"FAIL passing"$'\n'"$TEST_SET"

        # Prepare edits by each module
        for line in "${LINES[@]}"; do
                if ! TEST_LINE=($(egrep '^(FAIL|WARN)' <<<"$line")); then
                        continue
                fi
                TESTSET_CMD="${TEST_LINE[1]}"
                STAGING_DIR="$BASE_DIR/${i}_$TESTSET_CMD"
                if ! [ -f "$CHECKERS/$TESTSET_CMD" ]; then
                        continue
                fi
                CHECKER=$(realpath "$CHECKERS/$TESTSET_CMD")
                copy_files "$STAGING_DIR"
                # run test
                (cd "$STAGING_DIR" && $CHECKER "${TEST_LINE[@]:2}")

                ((i = i + 1))
        done
}

function remote_provide() {
        # copy files to student level account
        # might use rsync instead
        ssh "$REMOTE" "rm -rf ~/$BASE_DIR && mkdir -p ~/$BASE_DIR "
        scp -q -r "$BASE_DIR" "$REMOTE:~/$BASE_DIR/.."

        # For each directory
        # cd into it, find all files in directory and provide
        # TODO : Shorten this
        ssh -T "$REMOTE" bash -s <<EOF
                function provideAll() {
                        local files=\$(find . -maxdepth 1 -type f \
                                      | xargs -r  basename -a)
                        
                        if ! [ -z "\$files" ]; then 
                                yes | provide comp15 $HWNAME \$files > provide_output.txt
                        fi

                        for dir in */; do
                                if ! [ -d "\$dir" ]; then
                                        continue
                                fi
                                (cd \$dir && provideAll)
                        done
                }

                cd ~/$BASE_DIR && provideAll

EOF
        # Copy provide_output.txt's back to local
        scp -q -r "$REMOTE:~/$BASE_DIR" "$BASE_DIR"/..
}

function evaluate_results() {
        for directory in "$BASE_DIR"/*/; do
                dirname=$(basename "$directory")
                cmdName=${dirname#*_}
                cmd=$(realpath "$CHECKERS/$cmdName")
                (cd "$directory" && $cmd --test)
                assert_test "$?" "$cmdName"
        done
}

# Runs tests.  Passing test always runs.  Other tests are parsed from the
# testset and run if they are found.
function run_tests() {
        perform_edits
        remote_provide
        evaluate_results
}

# Lets run it!

validate_usage "$@"
setup "$@"
validate_assignment
run_tests

# rm -rf "$BASE_DIR"
