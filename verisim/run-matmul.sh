#!/usr/bin/env bash
bmark=matmul
zero_point_threshold=1200000
max_threshold=480000
max_score=10
bin=$(($((zero_point_threshold - max_threshold)) / max_score))
echo $bin
touch ../test/riscv-bmarks/matmul/matmul.c
make CONFIG=Lab5MSIConfig run-benchmarks > msi.out 2> msi.err
touch ../test/riscv-bmarks/matmul/matmul.c
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
    msi_cycle_count=$(grep "matmul_opt" msi.err | awk '{print $8}')
    mi_cycle_count=$(grep "matmul_opt" mi.err | awk '{print $8}')
    cycle_count=$((msi_cycle_count + mi_cycle_count))
    echo $msi_cycle_count
    echo $mi_cycle_count
    echo $cycle_count
    diff=$((zero_point_threshold - cycle_count))
    msi_diff=$((400000 - msi_cycle_count))
    echo $msi_diff
    msi_score=$(python -c "print(2.0 + max(0.0, min(${msi_diff} / float(60000.0), 3.0)))")
    echo $msi_score
    score=$(python -c "print(min(10.0,max(${msi_score}, ${diff} / float(${bin}))))")
    echo $score

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
