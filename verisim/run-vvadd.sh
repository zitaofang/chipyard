#!/usr/bin/env bash
bmark=vvadd
zero_point_threshold=85000
one_point_threshold=62000
two_point_threshold=49000
touch ../test/riscv-bmarks/vvadd/vvadd.c
make CONFIG=Lab5MSIConfig run-benchmarks > msi.out 2> msi.err
touch ../test/riscv-bmarks/vvadd/vvadd.c
make CONFIG=Lab5MIConfig run-benchmarks > mi.out 2> mi.err
rc=$?

# Default failing case
result_template="{
    \"score\": 0.0,
    \"stdout_visibility\": \"visible\"
}"

if grep -q SUCCESS mi.err; then
    cat msi.err
    cat mi.err
    msi_cycle_count=$(grep "vvadd_opt" msi.err | awk '{print $8}')
    mi_cycle_count=$(grep "vvadd_opt" mi.err | awk '{print $8}')
    cycle_count=$((msi_cycle_count + mi_cycle_count))
    echo $msi_cycle_count
    echo $mi_cycle_count
    echo $cycle_count
    score=0.0
    if [[ $cycle_count -lt $two_point_threshold ]]; then
        score=3.0
    elif [[ $cycle_count -lt $one_point_threshold ]]; then
        score=2.0
    elif [[ $cycle_count -lt $zero_point_threshold ]]; then
	score=1.0
    fi

        result_template="
        { \"score\": ${score},
          \"stdout_visibility\": \"visible\",
          \"leaderboard\":
            [
              {\"name\": \"Total Cycles\", \"value\": ${cycle_count}, \"order\": \"asc\"},
              {\"name\": \"MSI Cycles\", \"value\": ${msi_cycle_count}, \"order\": \"asc\"},
              {\"name\": \"MI Cycles\", \"value\": ${mi_cycle_count}, \"order\": \"asc\"}
            ]
        }"
else
    echo "Run Failed. Tail of commit log follows:"
    tail -n10 output/$bmark.riscv.out
fi

echo $result_template >> /autograder/results/results.json
