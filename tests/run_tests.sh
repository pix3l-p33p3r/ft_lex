#!/bin/sh

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Function to run a test
run_test() {
    local test_file="$1"
    local input_file="$2"
    local base_name=$(basename "$test_file" .l)
    
    echo "Testing ${base_name}..."
    
    # Generate lexer with ft_lex
    ./ft_lex "$test_file"
    if [ $? -ne 0 ]; then
        echo "${RED}Failed to generate lexer for ${base_name}${NC}"
        return 1
    fi
    
    # Compile generated lexer
    cc lex.yy.c -o "${base_name}_test"
    if [ $? -ne 0 ]; then
        echo "${RED}Failed to compile lexer for ${base_name}${NC}"
        return 1
    }
    
    # Run test with input
    if [ -f "$input_file" ]; then
        ./"${base_name}_test" < "$input_file" > "${base_name}_ft_lex.out"
    else
        ./"${base_name}_test" > "${base_name}_ft_lex.out"
    fi
    
    # Generate and run with flex for comparison
    flex "$test_file"
    cc lex.yy.c -o "${base_name}_flex"
    if [ -f "$input_file" ]; then
        ./"${base_name}_flex" < "$input_file" > "${base_name}_flex.out"
    else
        ./"${base_name}_flex" > "${base_name}_flex.out"
    fi
    
    # Compare outputs
    if diff "${base_name}_ft_lex.out" "${base_name}_flex.out"; then
        echo "${GREEN}${base_name} test passed!${NC}"
        return 0
    else
        echo "${RED}${base_name} test failed!${NC}"
        return 1
    fi
}

# Run all tests
cd tests
failed=0

run_test arithmetic.l arithmetic.txt || failed=$((failed + 1))
run_test parentheses.l parentheses.txt || failed=$((failed + 1))
run_test edge_cases.l edge_cases.txt || failed=$((failed + 1))

if [ $failed -eq 0 ]; then
    echo "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo "${RED}${failed} test(s) failed!${NC}"
    exit 1
fi
