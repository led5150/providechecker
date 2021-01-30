#!/bin/bash

rm -r providechecker_results

# Validates user has properly run program
function validate_usage() {
        # Check to make sure user has run the program correctly
        if [[ "$#" -lt 2 ]]; then
                echo "Invalid number of arguments provided"
                echo "Usage: $0 homework_name [--auto | --files file1 file2 file3 ...]"
                exit 1
        else
                echo "  ~~~ Welcome to ProvideChecker ~~~"
        fi
}

# removes line continuations from a given file
function remove_line_continuations() {
        parsed=$(sed -e ':x /[[:space:]]*\\$/ { N; s/[[:space:]]*\\\n//g; s/[[:space:]][[:space:]]*/ /g ; bx }' "$1")
        echo "$parsed"
}

function auto_mode() {
        # Run Auto Mode to create needed files
        printf "%s\n\n" "    *** running in auto mode ***"
        AUTO_DIR="$BASE_DIR/auto_created_files"
        echo "creating required files from testset in: "
        printf "%s\n\n" "$AUTO_DIR"

        # make the directory for the automagially created files
        mkdir -p "$AUTO_DIR"

        # Get an array of "user files" from the requried files
        IFS=' ' read -r -a USR_FILES <<< "$REQ_FILES"

        if [[ "${#USR_FILES[@]}" == 0 ]]; then
                echo -e "${YLW}No required files...Generating random file for submission${NC}"
                USR_FILES+=(random_"$i".cpp)
        fi

        # Get the full --assert-exec= command from testset
        ASRT_EXEC=($(echo "${TEST_SET[@]}" | grep -oP "(?<=(FAIL|WARN)\scompile_student\s--assert-exec=).+"))
        if [[ "${#ASRT_EXEC[@]}" -lt 2 ]]; then
                echo "'assert-exec=' option was used in $TEST_SET_PATH"
                echo "but was not properly configured"
                echo "Usage: compile_student [--assert-exec=EXEC_NAME] compilationCMD ..."
                exit 1
        fi
        EXEC="${ASRT_EXEC[0]}"         # Executalble name
        CMPL_CMD=("${ASRT_EXEC[@]:1}") # Compilation Command

        # Create the specified files parsed from the testset.
        # If the file has a ".cpp" extension, we overwrite it to make it
        # a working file using the file_maker.sh utility.
        for (( i=0; i<"${#USR_FILES[@]}"; i++ )); do
                file="$AUTO_DIR/${USR_FILES[i]}"
                touch "$file"
                if [[ "${USR_FILES[i]}" =~ .*".cpp" ]]; then
                        "$UTILS"/file_maker.sh cpp "${USR_FILES[i]}"
                        mv "${USR_FILES[i]}" "$AUTO_DIR"
                fi
                USR_FILES[i]="$file" # update USR_FILE array 
                                     # to hold full path to file
        done

        # If a Makefile was created in the above loop, or, if we use "make" as
        # our compilation command, but a Makefile is not required we need to 
        # edit/create it to ensure it is a working Makefile. Again we use the 
        # file_maker.sh utility
        if [[ -f "$AUTO_DIR/Makefile" || "${CMPL_CMD[0]}" == "make" ]]; then
                CPP=($(find $AUTO_DIR -type f -name \*.cpp))
                "$UTILS"/file_maker.sh make "$EXEC" "${CPP[0]##*\/}"
                mv "Makefile" "$AUTO_DIR"
                # Add path to Makfile if one does not exist
                [[ ! "${USR_FILES[*]}" =~ $AUTO_DIR/Makefile ]] \
                        && USR_FILES+=("$AUTO_DIR/Makefile")
        fi

}

# Sets variables we need for various purposes. Takes all arguments from
# command line
function set_variables() {
        
        # Used to display text in Color or reset to No Color
        export RED="\033[0;31m" # Red
        export GRN="\033[0;32m" # Green
        export LB="\033[1;34m"  # Light Blue
        export YLW="\033[1;33m" # Yellow
        export NC="\033[0m"     # No Color
        # Store homework name, user given files and set up file paths
        REMOTE="mkorma01@homework.cs.tufts.edu"
        HWNAME="$1"
        shift

        # Remove line continuations and store testset
        TEST_SET_PATH=/comp/15/grading/screening/testsets/"$HWNAME"
        TEST_SET=$(remove_line_continuations "$TEST_SET_PATH")

        ASSN_CONF=/comp/15/grading/assignments.conf

        # parse required files from testset
        REQ_FILES=$(echo "${TEST_SET[@]}" | grep -oP "(?<=(FAIL|WARN)\srequire\s).+" | sed 's/[ \t]*//')

        if [[ "${REQ_FILES[0]}" == "" ]]; then
                echo -e "${YLW}Warning: No Required Files were specified, but 'require'"
                echo -e "command was used in testset. Did you mean to specify filenames?"
                echo -e "'Require' test will NOT be run${NC}"
                echo ""
        fi

        CHECKERS=${BASH_SOURCE%/*}/checkers
        UTILS=${BASH_SOURCE%/*}/utils
        BASE_DIR="providechecker_results/$HWNAME"
        mkdir -p "$BASE_DIR"

        # Here we will evaluate if running in auto or user provided mode:
        # if auto, we create the files from the files listed after the 'require'
        # option in the testset, otherwise, we get the files listed on the 
        # command line from the user.
        if [[ "$1" == "-a" || "$1" == "--auto" ]]; then
                auto_mode
        elif [[ "$1" == "-f" || "$1" == "--files" ]]; then
                shift
                USR_FILES=("$@")
                if [[ "${#USR_FILES[@]}" == 0 ]]; then
                        echo -e "${RED}Error: ${NC}No files were specified"
                        exit 1
                fi
        else 
                echo "Invalid option"
                exit
        fi
        
}

# Requires filepath of directory
# Directory will be created and have user files copied into
function copy_files() {
        mkdir -p "$1"
        cp "${USR_FILES[@]}" "$1"
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
# Opens an editor for user to examine the faulty tests provide_output.txt file
# to help debug provide
function assert_test() {
        if [[ "$1" == 1 ]]; then
                if [[ "$4" == "print" ]]; then
                        echo -e "~~~~~~~ ${RED}$2 test failed.${NC} ~~~~~~~"
                fi
                echo "Check provide output to see what went wrong:"
                echo "Launching your default editor. Close file to continue..."
                echo ""
                sleep 2
                if [ "$(which code 2> /dev/null)" ]; then
                        "${EDITOR:-code}" --wait "$3"/provide_output.txt &
                        pid="$!"
                        wait "$pid"
                elif [ -n "$EDITOR" ]; then
                        "$EDITOR" "$3"/provide_output.txt
                else
                        "${EDITOR:-vi}" "$3"/provide_output.txt
                fi
        else
                if [[ "$4" == "print" ]]; then
                        echo -e "~~~~~~~ ${GRN}$2 test passed.${NC} ~~~~~~~"
                        echo ""
                fi
                # Clean up files if test passed
                rm -rf "$3" > /dev/null
        fi
}

# export function to use in compile_student
export -f assert_test

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
                if [[ "${REQ_FILES[0]}" == "" && "${TEST_LINE[1]}" == "require" ]]; then
                        continue
                fi
                copy_files "$STAGING_DIR"
                # run test
                (cd "$STAGING_DIR" && $CHECKER "${TEST_LINE[@]:2}")

                ((i = i + 1))
        done
}

function remote_provide() {
        # copy files to student level account
        # might use rsync instead
        ssh "$REMOTE" "rm -rf ~/$BASE_DIR && mkdir -p ~/$BASE_DIR"
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
        for dir in "$BASE_DIR"/*/; do
                if [[ "$(basename "$dir")" != "auto_created_files" ]]; then
                        dirname=$(basename "$dir")
                        cmdName=${dirname#*_}
                        cmd=$(realpath "$CHECKERS/$cmdName")
                        (cd "$dir" && $cmd --test)
                        assert_test "$?" "$cmdName" "$dir" "print"
                fi
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
