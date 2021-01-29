import pandas as pd
import itertools
import numpy as np
import subprocess
import shlex
import mysql.connector
from mysql.connector import Error
from utilities.chart import bar, \
    bar_char, \
    barh, \
    horizontal_bar_chart, \
    horizontal_bar_chart2, \
    horizontal_bar_chart3, \
    horizontal_bar_chart_final, \
    horizontal_bar_chart_final_single, \
    horizontal_bar_chart_two_in_one, \
    frequence_bar_chart


def dig_portnumber(server_name):
    cmd = f'dig SRV {server_name} +short'
    proc = subprocess.Popen(shlex.split(cmd), stdout=subprocess.PIPE)
    out, err = proc.communicate()
    port = out.decode("utf-8").split()[2]
    return port


def get_connection():
    # mysql -h mysql.service.consul -P 24531 -u root
    host = 'mysql.service.consul'
    port = dig_portnumber(host)
    connection = mysql.connector.connect(
        host=host,
        port=port,
        user='root',
        passwd='xcalar',
        database='xce_test_db'
    )
    return connection


def insert(log_list):
    try:
        connection = get_connection()

        mycursor = connection.cursor()
        query = '''
              INSERT IGNORE INTO xce_test_logs (test_timestamp, build_number, subset, delta, slave_host, status)
              VALUES (%s, %s, %s, %s, %s, %s)
            '''
        mycursor.executemany(query, log_list)
        connection.commit()
        print(mycursor.rowcount, "record inserted.")

    except Error as e:
        print("Error while connecting to MySQL", e)

    finally:
        if (connection.is_connected()):
            mycursor.close()
            connection.close()
            print("MySQL connection is closed")


def insert_info(lnfo_dict):
    try:
        connection = get_connection()

        mycursor = connection.cursor()
        query = '''
              INSERT IGNORE INTO xce_test_info (
              id, test_timestamp, job_name, displayName, building, description, duration, estimatedDuration, executor, fullDisplayName, queueId, url, builtOn, result)
              VALUES (  %(id)s, %(test_timestamp)s, %(job_name)s, %(displayName)s, %(building)s, %(description)s,
                        %(duration)s, %(estimatedDuration)s, %(executor)s, %(fullDisplayName)s, %(queueId)s, %(url)s, %(builtOn)s, %(result)s )
            '''

        mycursor.execute(query, lnfo_dict)
        connection.commit()
        print(mycursor.rowcount, "record inserted.")

    except Error as e:
        print("Error while connecting to MySQL", e)

    finally:
        if (connection.is_connected()):
            mycursor.close()
            connection.close()
            print("MySQL connection is closed")


def iter_row(cursor, size=10):
    while True:
        rows = cursor.fetchmany(size)
        if not rows:
            break
        for row in rows:
            yield row


def query_with_fetchall(sql=None, size=10):
    try:
        connection = get_connection()
        mycursor = connection.cursor()

        ## SQL
        mycursor.execute(sql)
        task_list = []
        volumn_list = []
        for row in iter_row(mycursor, size):
            volumn_list.append(float(row[0]))
            task_list.append(row[1])
            print(f'{row[1]} => {float(row[0])}')

        return task_list, volumn_list

    except Error as e:
        print("Error while connecting to MySQL", e)

    finally:
        if (connection.is_connected()):
            mycursor.close()
            connection.close()
            # print("MySQL connection is closed")


def query_with_fetchall_three_list(sql=None, size=10):
    # return stdev, average ,and task lists
    try:
        connection = get_connection()
        mycursor = connection.cursor()

        ## SQL
        mycursor.execute(sql)
        task_list = []
        volumn_list = []
        volumn2_list = []
        for row in iter_row(mycursor, size):
            volumn_list.append(float(row[0]))
            volumn2_list.append(float(row[1]))
            task_list.append(row[2])

        return task_list, volumn_list, volumn2_list

    except Error as e:
        print("Error while connecting to MySQL", e)

    finally:
        if (connection.is_connected()):
            mycursor.close()
            connection.close()
            # print("MySQL connection is closed")

def query_with_fetchall_dictionary(sql=None, size=10):
    try:
        connection = get_connection()
        mycursor = connection.cursor(dictionary=True, buffered=True)

        ## SQL
        print(sql)
        mycursor.execute(sql)
        rows_dict = mycursor.fetchall()

        return rows_dict

    except Error as e:
        print("Error while connecting to MySQL", e)

    finally:
        if (connection.is_connected()):
            mycursor.close()
            connection.close()
            # print("MySQL connection is closed")

##
## insight
##
def find_status_by_single_test( subtest, size=10, days=182):
    title = f'{subtest}\n Pass/ Fail in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
            test_timestamp,
            build_number,
            delta,
            status
      FROM xce_test_logs
      WHERE subset like '{subtest}' and DATEDIFF(NOW(), test_timestamp) <= {days}
      ORDER BY build_number desc
  '''

    result = query_with_fetchall_dictionary(sql, size)

    nums = []
    nums2 = []
    times = []
    status_list = []
    time_buildno = []

    for row in result:
        times.append(str(row['test_timestamp']))
        nums2.append(int(row['build_number']))
        nums.append(float(row['delta']))
        status_list.append(str(row['status']))
        time_buildno.append(str(row['build_number'])+' ('+str(row['test_timestamp']) + ')')

    # use len(nums) to get the bar counts
    # Image size coundn't over 2^6 inches.
    print(f'length: {len(nums)}')
    frequence_bar_chart(len(nums), times = times, nums=nums, nums2=time_buildno, status=status_list,  title=title, xlabel='(build_numbers)', ylabel='(seconds)')



def find_fail_the_most_frequently(size=10, days=182):
    title = f'top {size} Fail the most frequently in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
          count(*) as c,
          subset as task
      FROM xce_test_logs
      WHERE status = 'FAIL' and DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by c  desc limit {size}
  '''
    task_list, volumn_list = query_with_fetchall(sql, size)

    horizontal_bar_chart(size, tasks=task_list, nums=volumn_list, title=title, xlabel='(times)')
    # horizontal_bar_chart_final_single(size, tasks=task_list, nums=volumn_list, title=title, xlabel='(times)' )

def find_the_most_avg_execution_time(size=10, days=182):
    title = f'top {size} the most average execution time in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
            AVG(delta) as delta ,
            SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ':', 1), '/', -1)  as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by delta desc limit {size}
  '''
    task_list, volumn_list = query_with_fetchall(sql, size)
    horizontal_bar_chart(size, tasks=task_list, nums=volumn_list, title=title, xlabel='(seconds)')


def find_individual_the_most_execution_time(size=10, days=182):
    title = f'top {size} individual subtest takes the most execution time in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
          MAX(delta) as delta,
          subset as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by delta desc limit {size}
  '''
    task_list, volumn_list = query_with_fetchall(sql, size)
    horizontal_bar_chart(size, tasks=task_list, nums=volumn_list, title=title, xlabel='(seconds)')


def find_individual_the_most_average_execution_time(size=10, days=182):
    title = f'top {size} individual subtest take the most average execution time in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
          AVG(delta) as delta,
          subset as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by delta desc limit {size}
  '''

    task_list, volumn_list = query_with_fetchall(sql, size)
    horizontal_bar_chart(size, tasks=task_list, nums=volumn_list, title=title, xlabel='(seconds)')


def find_take_the_most_time_in_pass_tests(size=10, days=182):
    title = f'top {size} the most execution time in last {days} days (PASS only)'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
        SELECT
        a.delta as delta,
        a.subset as task
        FROM xce_test_logs a, xce_test_info b
        WHERE a.status = 'PASS' and  DATEDIFF(NOW(), a.test_timestamp) <= {days}
        and b.result = 'SUCCESS' and a.build_number = b.id
        GROUP BY task order by delta desc limit {size};
  '''
    task_list, volumn_list = query_with_fetchall(sql, size)
    horizontal_bar_chart(size, tasks=task_list, nums=volumn_list, title=title, xlabel='(seconds)')


def find_take_the_most_time_group_by_subname(size=10, days=182):
    title = f'top {size} the most execution time in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
          delta as delta,
          SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ':', 1), '/', -1)  as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by delta desc limit {size}
  '''
    task_list, volumn_list = query_with_fetchall(sql, size)
    horizontal_bar_chart(size, tasks=task_list, nums=volumn_list, title=title, xlabel='(seconds)')


def find_individual_the_most_stdev(size=10, days=182):
    title = f'top {size} individual subtest the most standard deviation in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
          STDDEV(delta) as delta ,
          subset as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by delta desc limit {size}
  '''
    task_list, volumn_list = query_with_fetchall(sql, size)
    horizontal_bar_chart(size, tasks=task_list, nums=volumn_list, title=title, xlabel='')


def find_the_most_stdev(size=10, days=182):
    title = f'top {size} test the most standard deviation in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
            STDDEV(delta) as delta ,
            SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ':', 1), '/', -1)  as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by delta desc limit {size}
  '''
    task_list, volumn_list = query_with_fetchall(sql, size)
    horizontal_bar_chart(size, tasks=task_list, nums=volumn_list, title=title, xlabel='')


# --------------------
# two in one chart
# --------------------
def find_individual_the_most_stdev_and_average(size=10, days=182):
    title = f'top {size} individual subtest the most average and stddev execution time in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
          AVG(delta) as delta ,
          STDDEV(delta) as delta2 ,
          subset as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by delta desc limit {size}
  '''
    task_list, volumn_list, volumn2_list = query_with_fetchall_three_list(sql, size)
    horizontal_bar_chart_final(size, tasks=task_list, nums=volumn_list, nums2=volumn2_list, title=title, xlabel='')


def find_the_most_stdev_average(size=10, days=182):
    title = f'top {size} test the most average with stddev execution time in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
      SELECT
            AVG(delta) as delta ,
            STDDEV(delta) as delta2 ,
            SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ':', 1), '/', -1)  as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
      GROUP BY task order by delta desc limit {size}
  '''
    task_list, volumn_list, volumn2_list = query_with_fetchall_three_list(sql, size)
    horizontal_bar_chart_final(size, tasks=task_list, nums=volumn_list, nums2=volumn2_list, title=title, xlabel='')


# -----------------------
# SQL query + Numpy.std()
# -----------------------
def find_individual_the_most_stdev_average_with_numpy(size=10, days=182):
    title = f'top {size} test the most average with stddev execution time in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    subset = 'src/bin/tests/pyTestNew/test_paging.py::testGroupByPaging[False-queryModes2-97-1-10-19-599-17-intCol]'
    sql = f'''
      SELECT
            delta ,
            subset  as task
      FROM xce_test_logs
      WHERE status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
    '''
    print(sql)
    task_list, volumn_list = query_with_fetchall(sql, size)

    # {task: [delta, ...]}
    data_dict = {}
    for i in range(len(task_list)):
        tsk = task_list[i]
        delta = volumn_list[i]

        if tsk in data_dict.keys():
            data_dict[tsk].append(delta)
        else:
            data_dict[tsk] = [delta]

    # calculate mean() and stddev()
    task_mean_std_dict={}

    for key, value in data_dict.items():
        task_mean_std_dict[key]=(np.mean(value), np.std(value))

    # sort top size
    # item[1] => mean value
    sorted_task_mean_std_dict = {k: v for k, v in sorted(task_mean_std_dict.items(), key=lambda item: item[1], reverse=True)}
    top_100_task_mean_std_dict = dict(itertools.islice(sorted_task_mean_std_dict.items(), size ))

    # split to lists
    tasks = top_100_task_mean_std_dict.keys()
    task_mean_list = [ item[0] for item in top_100_task_mean_std_dict.values() ]
    task_stddev_list = [ item[1] for item in top_100_task_mean_std_dict.values() ]

    horizontal_bar_chart_final(size, tasks=tasks, nums=task_mean_list, nums2=task_stddev_list, title=title, xlabel='')


# -----------------------------------------
# SQL query : one subset many build numbers
# -----------------------------------------
def find_one_subset_execution_time_among_build_numbers(size=10, days=182, subset=None ):
    title = f'{subset}\nexecution time in last {days} days'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
        SELECT
              delta ,
              build_number,
              subset  as task
        FROM xce_test_logs
        WHERE subset = '{subset}' and status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
        ORDER BY build_number desc
    '''
    task_list, volumn_list, volumn2_list = query_with_fetchall_three_list(sql, size)
    build_numbers = [int(i) for i in volumn2_list]
    bar(size, task_list, volumn_list, build_numbers, xlabel='build numbers', ylabel='execution time', title=title)


def find_one_subset_execution_time_among_build_numbers_slaves(size=10, days=182, subset=None, sort_by='delta', bar_color='red' ):
    title = f'{subset}\nexecution time in last {days} days sort by {sort_by}'
    print(f'\n## {title}')
    # SUBSTRING_INDEX(SUBSTRING_INDEX(subset, ' ', 1), ' ', -1) AS task
    sql = f'''
        SELECT
                delta ,
                build_number,
                slave_host,
                test_timestamp,
                subset  as task
        FROM xce_test_logs
        WHERE subset = '{subset}' and status = 'PASS' and  DATEDIFF(NOW(), test_timestamp) <= {days}
        ORDER BY {sort_by} desc
    '''
    result = query_with_fetchall_dictionary(sql, size)
    # print(result_dict)

    task_list = []
    volumn_list = []
    slave_list = []
    timestamp_list = []
    build_numbers = []
    build_slave_numbers = []

    for row in result:
        # {'delta': Decimal('2730.590'), 'build_number': 47641, 'slave_host': 'jenkins-slave-el7-node8-2',
        # 'task': 'src/bin/tests/pyTestNew/test_paging.py::testGroupByPaging[False-queryModes2-97-1-10-19-599-17-intCol]'}
        volumn_list.append(float(row['delta']))
        build_numbers.append(int(row['build_number']))
        slave_list.append(row['slave_host'])
        timestamp_list.append(row['test_timestamp'])
        task_list.append(row['task'])
        build_slave = f"{row['slave_host']}\n{int(row['build_number'])}\n{row['test_timestamp']}"
        build_slave_numbers.append(build_slave)

    bar(size, task_list, volumn_list, build_slave_numbers, xlabel='slave_host/ build numbers/ timestampe', ylabel='execution time', title=title, bar_color= bar_color)
