import argparse
from utilities.mysql_connect import \
    find_fail_the_most_frequently, \
    find_individual_the_most_execution_time, \
    find_individual_the_most_average_execution_time, \
    find_the_most_avg_execution_time, \
    find_the_most_stdev, \
    find_individual_the_most_stdev, \
    find_take_the_most_time_in_pass_tests, \
    find_take_the_most_time_group_by_subname, \
    find_individual_the_most_stdev_and_average, \
    find_the_most_stdev_average, \
    find_individual_the_most_stdev_average_with_numpy, \
    find_one_subset_execution_time_among_build_numbers, \
    find_one_subset_execution_time_among_build_numbers_slaves, \
    find_status_by_single_test


parser = argparse.ArgumentParser(description='Find the slowest job from XCE Tests log')
parser.add_argument('-d', '--days', type = int, metavar='', default=182, required=False, help = 'last n days')
parser.add_argument('-s', '--size', type = int, metavar='', default=10, required=False, help='top list size')
parser.add_argument('-mff', '--most_fail_frequently', action="store_true", help='Find fail the most frequently')
parser.add_argument('-mt', '--most_time', action="store_true", help='Find take the most of time')
parser.add_argument('-ms', '--most_stdev',action="store_true", help='Find the most of standard deviation')
args = parser.parse_args()

if __name__ == '__main__':
    # -----------------------
    # single test
    # -----------------------
    # find_status_by_single_test('io/test_export.py::test_multiple_parquet_telecom_prefixed', args.size, args.days)
    find_status_by_single_test('%test_multiple_parquet_telecom_prefixed%', args.size, args.days)


    # -----------------------
    # compare single subtest
    # -----------------------
    # find_one_subset_execution_time_among_build_numbers( args.size, args.days, 'src/bin/tests/pyTestNew/test_paging.py::testGroupByPaging[False-queryModes2-97-1-10-19-599-17-intCol]' )
    # find_one_subset_execution_time_among_build_numbers_slaves( args.size, args.days, 'src/bin/tests/pyTestNew/test_paging.py::testGroupByPaging[False-queryModes2-97-1-10-19-599-17-intCol]', sort_by='delta', bar_color='red' )
    # find_one_subset_execution_time_among_build_numbers_slaves( args.size, args.days, 'src/bin/tests/pyTestNew/test_paging.py::testGroupByPaging[False-queryModes2-97-1-10-19-599-17-intCol]', sort_by='slave_host', bar_color='orange' )
    # find_one_subset_execution_time_among_build_numbers_slaves( args.size, args.days, 'src/bin/tests/pyTestNew/test_paging.py::testGroupByPaging[False-queryModes2-97-1-10-19-599-17-intCol]', sort_by='build_number', bar_color='green' )
    # find_one_subset_execution_time_among_build_numbers_slaves( args.size, args.days, 'src/bin/tests/pyTestNew/test_paging.py::testGroupByPaging[False-queryModes2-97-1-10-19-599-17-intCol]', sort_by='test_timestamp', bar_color='blue' )
    # find_one_subset_execution_time_among_build_numbers_slaves( args.size, args.days, 'io/test_export.py::test_multiple_parquet_telecom_prefixed', sort_by='test_timestamp', bar_color='blue' )
    # -----------------
    # two in one chart
    # -----------------
    # find_the_most_stdev_average( args.size, args.days )
    # find_individual_the_most_stdev_and_average( args.size, args.days )

    # -----------------
    # single subset
    # -----------------
    # find_individual_the_most_stdev_average_with_numpy( args.size, args.days )

    # -----------------
    # others
    # -----------------
    # find_fail_the_most_frequently( args.size, args.days )
    # find_individual_the_most_execution_time( args.size, args.days )
    # find_individual_the_most_average_execution_time( args.size, args.days )
    # find_individual_the_most_stdev( args.size, args.days )


    # find_the_most_stdev( args.size, args.days )



    #find_take_the_most_time_in_pass_tests( args.size, args.days )
    #find_take_the_most_time_group_by_subname( args.size, args.days )

    # find_the_most_avg_execution_time( args.size, args.days )

    exit()

    if args.most_fail_frequently: find_fail_the_most_frequently( args.size, args.days )
    if args.most_time: find_individual_the_most_execution_time( args.size, args.days )
    if args.most_stdev: find_the_most_stdev( args.size, args.days )
    # find_take_the_most_avg_time(10, args.days)
