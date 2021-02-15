#!/bin/bash

rm -rf providechecker_results

# Validates user has properly run program
function validate_usage() {
    if [[ "$#" -lt 2 ]]; then
            echo "Invalid number of arguments provided"
            echo "Usage: $0 homework_name [--auto | --files file1 file2 file3 ...]"
            exit 1
    else
            printf "%s\n\n" "        ~~~ Welcome to ProvideChecker ~~~"
    fi
}

# removes line continuations from a given file
function remove_line_continuations() {
    parsed=$(sed -e ':x /[[:space:]]*\\$/ { N; s/[[:space:]]*\\\n//g; s/[[:space:]][[:space:]]*/ /g ; bx }' "$1")
    echo "$parsed"
}

function auto_mode() {
    # Run Auto Mode to create needed files
    printf "%s\n\n" "          *** running in auto mode ***"
    AUTO_DIR="$HW_TEMP_DIR/auto_created_files"

    # make the directory for the automagially created files
    mkdir -p "$AUTO_DIR"

    # USR_FILES array needs to have the names of required files in order
    # for the files to be able to be created properly.
    read -r -a USR_FILES <<< "${REQ_FILES[@]}"


    if [[ "$NUM_REQ" == 0 ]]; then
            echo -e "${YLW}No required files...Generating random file for submission${NC}"
            USR_FILES+=(random_"$i".cpp)
    fi

    # Get the full --assert-exec= command from testset
    read -ra ASRT_EXEC < <(echo  "$TEST_SET" | grep -v "#" | grep -oP "(?<=--assert-exec=).+$")

    # quick sanity check for --assert-exec option
    if [[ "${ASRT_EXEC[0]}" != "" && "${#ASRT_EXEC[@]}" -lt 2 ]]; then
            error "'--assert-exec=' option was used but was not properly configured\n" \
                  "${NC}Please edit: $TEST_SET_PATH" \
                  "${NC}Usage: compile_student [--assert-exec=EXEC_NAME] compilationCMD ..."
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
    # our compilation command, we edit/create it to ensure it is a 
    # working Makefile using the file_maker.sh utility
    if [[ -f "$AUTO_DIR/Makefile" || "${CMPL_CMD[0]}" == "make" ]]; then
            CPP=($(find $AUTO_DIR -type f -name \*.cpp))
            "$UTILS"/file_maker.sh make "$EXEC" "${CPP[0]##*\/}"
            mv "Makefile" "$AUTO_DIR"
            # Add path to Makfile if one does not exist
            [[ ! "${USR_FILES[*]}" =~ $AUTO_DIR/Makefile ]] \
                    && USR_FILES+=("$AUTO_DIR/Makefile")
    fi

}

function warning() {
    i=0
    echo -en "${YLW}Warning: "
    for message in "$@"; 
    do
            if [[ "$i" == 0 ]]; then
                    echo -e "$message"
            else 
                    echo -e "         $message"
            fi
            (( i++ ))
    done
    echo -e "${NC}"
}

function error() {
    i=0
    echo -en "${RED}Error: "
    for message in "$@"; 
    do
            if [[ "$i" == 0 ]]; then
                    echo -e "$message"
            else 
                    echo -e "       $message"
            fi
            (( i++ ))
    done
    echo -e "${NC}"
    cleanup 1
}



function sanity_checks() {

    if [[ "${#USR_FILES[@]}" == 0 ]]; then
            error "No files were specified"
    fi
    
    if [[ "$1" != "-a" && "${#USR_FILES[@]}" -lt "${ASGN_MAP[files]}" ]]; then
            error "Too few files provided!" \
                    "You supplied: ${#USR_FILES[@]} files" \
                    "The assignment requires exactly ${ASGN_MAP[files]}"
    fi

    if [[ "${ASGN_MAP[minfiles]}" -gt "$NUM_REQ" ]]; then
            warning "minfiles was set to a number greater" \
                    "than the number of required files specified!"
            if [[ "$1" == "-a" || "$1" == "--auto" ]]; then
                    error "Auto mode is not supported with the current" \
                            "homework configuration. Please check the asignment" \
                            "config, or run with user supplied files."
            fi
    fi
    
    if [[ "${ASGN_MAP[maxfiles]+_}" && "${ASGN_MAP[maxfiles]}" -lt "$NUM_REQ" ]]; then
            error "maxfiles was set to a number less" \
                    "than the number of required files specified!" \
                    "${NC}Please edit the testset  at: $TEST_SET_PATH" \
                    "or the assignment config at: $ASSN_CONF"
    fi

    if [[ "${ASGN_MAP[files]+_}" && "$NUM_REQ" -gt "${ASGN_MAP[files]}" ]]; then
            error "Number of required files is > than" \
                    "the number of 'files' allowed by this submission!" \
                    "${NC}Please edit the testset  at: $TEST_SET_PATH" \
                    "or the assignment config at: $ASSN_CONF"
    fi
    if [[ "${ASGN_MAP[files]+_}" && "$NUM_REQ" -lt "${ASGN_MAP[files]}" ]]; then
            if [[ "$1" == "-a" || "$1" == "--auto" ]]; then
                    warning "Number of required files is < than the " \
                            "number of 'files' allowed by this submission!"\
                            "Are you sure you meant to do this?" \
                            "Creating extra files for you..."
                        i="$NUM_REQ"
                    while [[ "$i" -lt "${ASGN_MAP[files]}" ]];
                    do
                            touch "$AUTO_DIR/extra_file_$i"
                            USR_FILES+=("$AUTO_DIR/extra_file_$i")
                            ((i++))
                    done
            
            else
                    warning "Number of required files is less than the value of" \
                            "'files' in $ASSN_CONF" \
                            "You provided more than the number of required files"
                    echo -e "${LB}In order to proceed we need to make temporary"
                    echo -e "copies of some of your originals, which will then be deleted${NC}"
                    read -rp "Would you like to continue? [Y/n]: " proceed
                    if [[ "$proceed" != "Y" ]]; then
                            echo -e "${YLW}Files have not been altered. Exiting"
                            exit 0
                    else 
                            mkdir extra_files
                            tempreq=${REQ_FILES[*]} 
                            for (( i=0; i<"${#USR_FILES[@]}"; i++));
                            do      
                                    if  grep -q "${USR_FILES[i]#*/}" <<< "$tempreq"; then
                                            continue
                                    else   
                                            cp "${USR_FILES[i]}" "extra_files/extra_file_$i"
                                            USR_FILES[i]="extra_files/extra_file_$i"
                                    fi
                            done
                    fi
            fi
    fi
    
    if [[ "${ASGN_MAP[files]+_}" && "${#USR_FILES[@]}" -gt "${ASGN_MAP[files]}" 
        || "${ASGN_MAP[maxfiles]+_}" && "${#USR_FILES[@]}" -gt "${ASGN_MAP[maxfiles]}" ]]; then
            error "You supplied more than the maximum number" \
                    "of files allowed by this submission!"
    fi
}

# Sets variables we need for various purposes. Takes all arguments from
# command line.
# Store homework name, user given files and set up file paths
function set_variables() {
    
    # Used to display text in Color or reset to No Color
    export RED="\033[0;31m" # Red
    export GRN="\033[0;32m" # Green
    export LB="\033[1;34m"  # Light Blue
    export YLW="\033[1;33m" # Yellow
    export NC="\033[0m"     # No Color

    REMOTE="mkorma01@homework.cs.tufts.edu"
    HWNAME="$1"
    shift

    # Remove line continuations and store testset
    TEST_SET_PATH=/comp/15/grading/screening/testsets/"$HWNAME"
    TEST_SET=$(remove_line_continuations "$TEST_SET_PATH")
    
    # parse required files from testset
    # read -ra REQ_FILES < <(echo "$TEST_SET" | grep -oP "(?<=(FAIL|WARN)\srequire\s).+")	# regex pattern only matched with exactly 1 whitespce char in between 
    read -ra REQ_FILES < <(echo  "$TEST_SET" | grep -v "#" | grep -w "require")
    REQ_FILES=("${REQ_FILES[@]:2}")
    NUM_REQ=${#REQ_FILES[@]}

    # If require is not used, require is not run.
    if [[ "$NUM_REQ" -gt 0 ]]; then
            RUN_REQ=1       # Flag to determine if we run 'require' test. 
                            # 1 == run, 0 == don't run
    else
        #TODO: Find a place to make this work?
        #     warning "No Required Files were specified, but 'require'" \
        #             "command was used in testset. Did you mean to specify filenames?" \
        #             "'Require' test will NOT be run"
            RUN_REQ=0
    fi

    # Store path to assignments.conf
    ASSN_CONF=/comp/15/grading/assignments.conf
    ASIGN=$(remove_line_continuations "$ASSN_CONF")

    # find HW config in assignments.conf and store it
    read -ra HW < <(echo "$ASIGN" | grep -oP "^[^#].+(?>$HWNAME).+")

    # Map each parameter from HW config to its value
    declare -gA ASGN_MAP
    for item in "${HW[@]}";
    do
            ASGN_MAP["$(cut -d'=' -f1 <<< "$item")"]=$(cut -d'=' -f2 <<< "$item")
    done
    export ASGN_MAP

    BASE_DIR="providechecker_results"
    CHECKERS=${BASH_SOURCE%/*}/checkers     # Path to checkers
    UTILS=${BASH_SOURCE%/*}/utils           # Path to utilities
    HW_TEMP_DIR="$BASE_DIR/$HWNAME"         # Temp directory for bulding submissions
    mkdir -p "$HW_TEMP_DIR"

    # Here we will evaluate if running in auto or user provided mode:
    # if auto, we create the files from the files listed after the 'require'
    # option in the testset, otherwise, we get the files listed on the 
    # command line from the user.
    if [[ "$1" == "-a" || "$1" == "--auto" ]]; then
            auto_mode
            sanity_checks "$1"
    elif [[ "$1" == "-f" || "$1" == "--files" ]]; then
            shift
            USR_FILES=("$@")
            sanity_checks "$1"
    else 
            echo "Invalid option"
            cleanup 1
    fi
}

# Requires filepath of directory
# Directory will be created and have user files copied into
function copy_files() {
    mkdir -p "$1"
    cp "${USR_FILES[@]}" "$1"
}

# Asserts that the assignment has been added to assignments.conf
# and is uncommented
function validate_assignment() {
    if ! ASSIGN=$(remove_line_continuations "$ASSN_CONF" | grep -oP "^[^#].+(?<=$HWNAME).*$"); then
            error "Assignment doesn't exist in $ASSN_CONF or is commented out."
                    "Please add the assignment to assignments.conf and try again."
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
            echo -e "${LB}Check provide output to see what went wrong:"
            echo -e "Launching your default editor. Close file to continue...${NC}"
            echo ""
            sleep 2
            
            if [ -n "$EDITOR" ]; then
                    "$EDITOR" "$3"/provide_output.txt
            elif [ "$(which code 2> /dev/null)" ]; then
                    code --wait "$3"/provide_output.txt
            else
                    vim "$3"/provide_output.txt
            fi
    else
            if [[ "$4" == "print" ]]; then
                    echo -e "~~~~~~~ ${GRN}$2 test passed.${NC} ~~~~~~~"
                    echo ""
            fi
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
            STAGING_DIR="$HW_TEMP_DIR/${i}_$TESTSET_CMD"

            # The three checks below do the folowing respectively:
            # 1. Skips making files for tests not specified in testset
            # 2. Skips running the 'require' test if no required files were 
            #    specified
            # 3. Skips 'not_allowed' test if we don't have room to make a not 
            #    allowed file
            if ! [ -f "$CHECKERS/$TESTSET_CMD" ]; then
                    continue
            fi

            if [[ "$RUN_REQ" == 0 && "$TESTSET_CMD" == "require" ]]; then
                    continue
            fi
            
            if [[ "$TESTSET_CMD" == "not_allowed" && "${ASGN_MAP[files]+_}" ]]; then 
                    if [[ "$NUM_REQ" == "${ASGN_MAP[files]}" ]]; then
                            warning "Unable to make a 'Not Allowed' file!!" \
                                    "Number of required files is >= the number of"\
                                    "files allowed by this assignment's config." \
                                    "Not Allowed test is unable to run"
                                    continue
                    fi                        
            fi
            CHECKER=$(realpath "$CHECKERS/$TESTSET_CMD")
            copy_files "$STAGING_DIR"
            # run test
            (cd "$STAGING_DIR" && $CHECKER "${TEST_LINE[@]:2}")

            (( i++ ))
    done
}

function remote_provide() {
    # copy files to student level account
    # might use rsync instead
    ssh "$REMOTE" "rm -rf ~/$HW_TEMP_DIR && mkdir -p ~/$HW_TEMP_DIR"
    scp -q -r "$HW_TEMP_DIR" "$REMOTE:~/$HW_TEMP_DIR/.."

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

    cd ~/$HW_TEMP_DIR && provideAll

EOF
    # Copy provide_output.txt's back to local
    scp -q -r "$REMOTE:~/$HW_TEMP_DIR" "$HW_TEMP_DIR"/..
}

function evaluate_results() {
    for dir in "$HW_TEMP_DIR"/*/; do
            if [[ "$(basename "$dir")" != "auto_created_files" ]]; then
                    dirname=$(basename "$dir")
                    cmdName=${dirname#*_}
                    cmd=$(realpath "$CHECKERS/$cmdName")
                    (cd "$dir" && $cmd --test)
                    assert_test "$?" "$cmdName" "$dir" "print"
            fi
    done
}

# Takes all arguments passed in from command line
function setup() {
    set_variables "$@"
    
}

# Runs tests.  Passing test always runs.  Other tests are parsed from the
# testset and run if they are found.
function run_tests() {
    perform_edits
    remote_provide
    evaluate_results
}

function cleanup(){
    find . -maxdepth 1 -type d -name "extra_files" -exec rm -r {} \;
    rm -rf "$BASE_DIR"
    exit "$1"
}

# Lets run it!

validate_usage "$@"
setup "$@"
validate_assignment
run_tests
cleanup 0


