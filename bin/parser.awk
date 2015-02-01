BEGIN {
    FS=" "
    #global variables for calculating qps
    SECOND_COUNT = 0
    QUERY_SUM = 0
    #global variables for calculating value average 
    VALUE_COUNT = 0
    VALUE_SUM = 0
    #global variables for calculating succ rate
    COUNT = 0
    #global variables for calculatinf name number
    NAME_COUNT = 0
}

/\[src\/worker/ {
    #1. handle calculating qps
    #query_time_count: key-value array, record number of query per second
    query_time_count[$2" "substr($3,1,length($3) - 1)]++
    
    #2.handle calculating value average
    #get "value"
    value = substr($NF,index($NF,"=") + 1)
    if(value != "") {
        VALUE_SUM += value
        VALUE_COUNT++
    }
    
    #3. handle calculating succ rate
    COUNT++
    #get if succ
    if_succ = substr($8,index($8,"=") + 1)
    if(if_succ == 1) {
        succ_status["YES"]++
    } else {
        succ_status["NO"]++
    }
    
    #4. handle calculating name_num
    #get name
    name = substr($11,index($11,"=") + 1)
    if(name != "") {
        name_record[name]++
    }
}

END {
    #1. calculate qps
    for(time in query_time_count) {
        SECOND_COUNT++
        QUERY_SUM += query_time_count[time]
    }
    if(SECOND_COUNT != 0) {
        printf("qps=%-20.3f\n",QUERY_SUM / SECOND_COUNT)
    } else {
        print "qps=N/A"
    }

    #2. calculate value_avg
    if(VALUE_COUNT != 0) {
        printf("value_avg=%-20.3f\n",VALUE_SUM / VALUE_COUNT)
    } else {
        print "value_avg=N/A"
    }

    #3. calculate succ_rate
    if(COUNT !=0 ) {
        printf("succ_rate=%-20.3f\n",succ_status["YES"] / COUNT)
    } else {
        print "succ_rate=N/A"
    }
    
    #4. calculate name_num
    for (n in name_record) {
        NAME_COUNT++
    }
    printf("name_num=%-20d\n",NAME_COUNT) 
}
