#!/bin/bash

set -e

PWD=$(get_pwd "${BASH_SOURCE[0]}")

session_id="${1}"

step="testing_${session_id}"

init_log "${step}"

sql_dir="${PWD}/${session_id}"

function generate_queries() {
  #going from 1 base to 0 base
  tpcds_id=$((session_id - 1))
  tpcds_query_name="query_${tpcds_id}.sql"
  query_id=1
  for p in $(seq 1 99); do
    q=$(printf %02d "${query_id}")
    template_filename="query${p}.tpl"
    start_position=""
    end_position=""
    while IFS= read -r pos; do
      if [ "${start_position}" == "" ]; then
        start_position="${pos}"
      else
        end_position="${pos}"
      fi
    done < <(grep -n "${template_filename}" < "${sql_dir}/${tpcds_query_name}" | awk -F ':' '{print $1}')

    #get the query number (the order of query execution) generated by dsqgen
    file_id=$(sed -n "${start_position},${start_position}p" "${sql_dir}/${tpcds_query_name}" | awk -F ' ' '{print $4}')
    file_id=$((file_id + 100))
    filename="${file_id}.${BENCH_ROLE}.${q}.sql"

    #add explain analyze
    printf 'print "set role %s;\n:EXPLAIN_ANALYZE\n" > %s' "${BENCH_ROLE}" "${sql_dir}/${filename}"
    printf "set role %s;\n:EXPLAIN_ANALYZE\n" "${BENCH_ROLE}" > "${sql_dir}/${filename}"
    echo "sed -n ${start_position},${end_position}p ${sql_dir}/${tpcds_query_name} >> ${sql_dir}/${filename}"
    sed -n "${start_position},${end_position}p" "${sql_dir}/${tpcds_query_name}" >> "${sql_dir}/${filename}"
    query_id=$((query_id + 1))
    echo "Completed: ${sql_dir}/${filename}"
  done
  echo "rm -f ${sql_dir}/query_*.sql"
  rm -f "${sql_dir}/${tpcds_query_name}"

  echo ""
  echo "queries 14, 23, 24, and 39 have 2 queries in each file.  Need to add :EXPLAIN_ANALYZE to second query in these files"
  echo ""
  arr=("*.${BENCH_ROLE}.14.sql" "*.${BENCH_ROLE}.23.sql" "*.${BENCH_ROLE}.24.sql" "*.${BENCH_ROLE}.39.sql")

  for z in "${arr[@]}"; do
    myfilename=${sql_dir}/${z}
    echo "myfilename: ${myfilename}"
    # shellcheck disable=SC2086
    pos=$(grep -n ";" < ${myfilename} | awk -F ':' '{ if (NR > 1) print $1}' | head -1)
    pos=$((pos + 1))
    # shellcheck disable=SC2086
    sed -i "${pos}i:EXPLAIN_ANALYZE" ${myfilename}
  done
}

if [ "${RUN_QGEN}" = "true" ]; then
  generate_queries
fi

tuples="0"
for i in "${sql_dir}"/*.sql; do
  start_log
  id=$(basename "${i}" | awk -F '.' '{print $1}')
  schema_name="${session_id}"
  table_name=$(basename "${i}" | awk -F '.' '{print $3}')

  if [ "${EXPLAIN_ANALYZE}" == "false" ]; then
    log_time "psql -d gpadmin -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE=\"\" -f ${i} | wc -l"
    tuples=$(
      psql -d gpadmin -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE="" -f "${i}" | wc -l
      exit "${PIPESTATUS[0]}"
    )
    tuples=$((tuples - 1))
  else
    myfilename=$(basename "${i}")
    mylogfile="${TPC_DS_DIR}/log/${session_id}.${myfilename}.multi.explain_analyze.log"
    log_time "psql -d gpadmin -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE=\"EXPLAIN ANALYZE\" -f ${i}"
    psql -d gpadmin -v ON_ERROR_STOP=1 -A -q -t -P pager=off -v EXPLAIN_ANALYZE="EXPLAIN ANALYZE" -f "${i}" > "${mylogfile}"
    tuples="0"
  fi

  #remove the extra line that \timing adds
  print_log "${id}" "${schema_name}" "${table_name}" "${tuples}"
done

end_step "${step}"
