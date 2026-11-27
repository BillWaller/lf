
BEGIN {
begin = 1
    st_err_cnt = 0
    t_err_cnt = 0
    p_ln_no = 0
    rc = getline
    while (rc) {
        if ($0 == "") {
            rc = getline
            continue
        }
        if (begin == 1) {
            printf("line_no errors\n")
            printf("------- ------\n")
            begin = 0
        }
        ln_no = $1
        err_cnt = $2
        action = ""
        if ($3 == "read")
            action = "r"
        else if ($3 == "write")
            action = "w"
        if (p_ln_no != 0 && ln_no != p_ln_no) {
            printf("%6s%1s %6s\n", p_ln_no, p_action, st_err_cnt)
            st_err_cnt = 0
        }
        p_ln_no = ln_no
        p_action = action
        st_err_cnt += err_cnt
        t_err_cnt += err_cnt
        rc = getline
    }

    printf("%6s%1s %6s\n", p_ln_no, p_action, st_err_cnt, $3)
    printf("        ------\n")
    printf("total   %6s (2 x %s)\n", t_err_cnt, t_err_cnt / 2)
}
