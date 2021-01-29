import numpy as np
import matplotlib as mp
import matplotlib.pyplot as plt
import pandas as pd

def frequence_bar_chart(size, times=[], nums=[], nums2=[], status=[],  title=None, xlabel='', ylabel='', bar_color='green'):

    def autolabel(bars):
        """Attach a text label above each bar in *rects*, displaying its height."""
        for bar in bars:
            height = bar.get_height()
            ax.annotate('{}'.format(height),
                        xy=(bar.get_x() + bar.get_width() / 2, height),
                        xytext=(0, 3),  # 3 points vertical offset
                        textcoords="offset points",
                        ha='center', va='bottom')

    fig, ax = plt.subplots()
    ax.set_xticklabels(nums , rotation='vertical')
    plt.style.use('ggplot')
    x_pos = [i for i, _ in enumerate(nums)]

    a = plt.bar(x_pos, nums, color=bar_color, alpha=0.6)

    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)

    plt.xticks(x_pos, nums2)
    fig.set_size_inches(w=0.3 * size, h=8, forward=True)
    autolabel(a)

    # set margins ( no white space )
    plt.margins(x=0)

    # set font
    font = {'family': 'normal',
            'weight': 'bold',
            'size': 10}

    plt.rc('font', **font)
    # set color
    for i in range(len(status)):
        if status[i] == 'FAIL':
            a[i].set_color('r')
    plt.show()
    plt.savefig(f'{title}.png')


def bar(top_n, tasks, nums, nums2, xlabel='', ylabel='', title='', bar_color='green'):
    def autolabel(bars):
        """Attach a text label above each bar in *rects*, displaying its height."""
        for bar in bars:
            height = bar.get_height()
            ax.annotate('{}'.format(height),
                        xy=(bar.get_x() + bar.get_width() / 2, height),
                        xytext=(0, 3),  # 3 points vertical offset
                        textcoords="offset points",
                        ha='center', va='bottom')

    fig, ax = plt.subplots()
    # ax.set_xticklabels(nums2)
    plt.style.use('ggplot')
    x_pos = [i for i, _ in enumerate(nums2)]

    a = plt.bar(x_pos, nums, color=bar_color, alpha=0.6)
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.title(title)

    plt.xticks(x_pos, nums2)
    fig.set_size_inches(w=0.5 * top_n, h=8, forward=True)
    autolabel(a)
    plt.show()


def bar_char(tasks, volumn, xlabel='', ylabel='', title=''):
    fig, ax = plt.subplots()
    x=np.arange(len(tasks))                     #產生X軸座標序列
    plt.bar(x, volumn, tick_label=tasks, color=(0.2, 0.4, 0.6 ))        #繪製長條圖
    plt.title(title)                            #設定圖形標題
    plt.xlabel(xlabel)                          #設定X軸標籤
    plt.ylabel(ylabel)                          #設定Y軸標籤
    plt.xticks(rotation=90)

    fig.set_size_inches(12,6,forward=True)
    plt.show()


def barh(tasks, nums, xlabel='', ylabel='', title=''):
    a_vals = tasks
    b_vals = nums
    ind = np.arange(len(tasks))
    width = 0.5

    # Set the colors
    colors = ['b', 'g', 'r', 'c', 'm', 'y', 'g']

    def autolabel(bars):
        # attach some text labels
        for i, bar in enumerate(bars):
            width = bar.get_width()
            # ax.text(width * 0.9,  i + .25, str(width), color='blue', fontweight='bold')
            ax.text(width + 10,
                    bar.get_y() + bar.get_height() / 2,
                    '%d' % int(width),
                    ha='right', va='center')

    # make the plots
    fig, ax = plt.subplots()
    a = ax.barh(ind, a_vals, width, color=colors)  # plot a vals
    b = ax.barh(ind + width, b_vals, width, color=colors, alpha=0.5)  # plot b vals
    ax.set_yticks(ind + width)  # position axis ticks
    ax.set_yticklabels(tasks)  # set them to the names
    ax.legend((a[0], b[0]), ['a', 'b'], loc='center right')

    autolabel(a)
    # autolabel(b)
    fig.set_size_inches(12,6,forward=True)
    plt.show()


def horizontal_bar_chart(top_n, tasks, nums, xlabel='', ylabel='', title=''):
    print(title)
    data_normalizer = mp.colors.Normalize()
    color_map = mp.colors.LinearSegmentedColormap(
        "my_map",
        {
            "red": [(0, 1.0, 1.0),
                    (1.0, .5, .5)],
            "green": [(0, 0.5, 0.5),
                      (1.0, 0, 0)],
            "blue": [(0, 0.50, 0.5),
                     (1.0, 0, 0)]
        }
    )


    # tip text
    # Set the colors
    colors = ['b', 'g', 'r', 'c', 'm', 'y', 'g']
    def autolabel(bars):
        # attach some text labels
        for bar in bars:
            width = bar.get_width()
            ax.text(width, bar.get_y() + bar.get_height() / 2,
                    '%d' % int(width),
                    ha='right', va='center')
    #
    plt.rcdefaults()
    fig, ax = plt.subplots()

    # Example data
    tasks = tasks
    y_pos = np.arange(len(tasks))
    performance = nums
    error = np.random.rand(len(tasks))

    a= ax.barh(y_pos, performance, align='center', color=colors, alpha=0.5)
    ax.set_yticks(y_pos)
    short_name_tasks = []
    for tsk in tasks:
        short_name_tasks.append( tsk.split('::')[-1] )
    ax.set_yticklabels(short_name_tasks)
    ax.invert_yaxis()           # labels read top-to-bottom
    ax.set_xlabel(xlabel)
    ax.set_title(title)
    #
    ax.spines['right'].set_visible(False)
    ax.spines['top'].set_visible(False)
    ax.patch.set_facecolor('#FFFFFF')
    ax.spines['bottom'].set_color('#CCCCCC')
    ax.spines['bottom'].set_linewidth(1)
    ax.spines['left'].set_color('#CCCCCC')
    ax.spines['left'].set_linewidth(1)
    autolabel(a)

    if top_n <= 10:
        height = 2+ top_n*0.2
    elif top_n > 10:
        height = 2 + top_n*0.2

    fig.set_size_inches(13, height ,forward=True)
    plt.show()
    # plt.savefig(f'{title}.png')


def horizontal_bar_chart_two_in_one(top_n, tasks, nums, nums2, xlabel='', ylabel='', title=''):
    print(title)
    data_normalizer = mp.colors.Normalize()
    color_map = mp.colors.LinearSegmentedColormap(
        "my_map",
        {
            "red": [(0, 1.0, 1.0),
                    (1.0, .5, .5)],
            "green": [(0, 0.5, 0.5),
                      (1.0, 0, 0)],
            "blue": [(0, 0.50, 0.5),
                     (1.0, 0, 0)]
        }
    )


    # tip text
    # Set the colors
    colors = ['b', 'g', 'r', 'c', 'm', 'y', 'g']
    def autolabel(bars):
        # attach some text labels
        for bar in bars:
            width = bar.get_width()
            ax.text(width + 6, bar.get_y() + bar.get_height() / 2,
                    '%d' % int(width),
                    ha='right', va='center')
    #
    plt.rcdefaults()
    fig, ax = plt.subplots()

    # Example data
    tasks = tasks
    y_pos = np.arange(len(tasks))
    performance = nums
    performance2 = nums2
    error = np.random.rand(len(tasks))

    aaa= ax.barh(y_pos, performance, align='center', color='yellow', alpha=0.5)
    bbb= ax.barh(y_pos, performance2, align='center', color='blue', alpha=0.5)

    ax.set_yticks(y_pos)
    short_name_tasks = []
    for tsk in tasks:
        short_name_tasks.append( tsk.split('::')[-1] )
    ax.set_yticklabels(short_name_tasks)
    ax.invert_yaxis()           # labels read top-to-bottom
    ax.set_xlabel(xlabel)
    ax.set_title(title)
    #
    ax.spines['right'].set_visible(False)
    ax.spines['top'].set_visible(False)
    ax.patch.set_facecolor('#FFFFFF')
    ax.spines['bottom'].set_color('#CCCCCC')
    ax.spines['bottom'].set_linewidth(1)
    ax.spines['left'].set_color('#CCCCCC')
    ax.spines['left'].set_linewidth(1)
    autolabel(aaa)
    autolabel(bbb)

    if top_n <= 10:
        height = 2+ top_n*0.2
    elif top_n > 10:
        height = 2 + top_n*0.2

    fig.set_size_inches(13, height ,forward=True)
    plt.show()
    # plt.savefig(f'{title}.png')



def horizontal_bar_chart2(top_n, tasks, nums, nums2, xlabel='', ylabel='', title=''):
    print(title)

    # tip text
    # Set the colors
    colors = ['b', 'g', 'r', 'c', 'm', 'y', 'g']
    def autolabel(bars):
        # attach some text labels
        for bar in bars:
            width = bar.get_width()
            ax.text(width + 6, bar.get_y() + bar.get_height() / 2,
                    '%d' % int(width),
                    ha='right', va='center')
    #
    plt.rcdefaults()
    fig, ax = plt.subplots()

    # Example data
    tasks = tasks
    y_pos = np.arange(len(nums))
    performance = nums

    a= ax.barh(y_pos, performance, xerr=nums2,  align='center', color=colors, alpha=0.5)
    ax.set_yticks(y_pos)
    short_name_tasks = []
    for tsk in tasks:
        short_name_tasks.append( tsk.split('::')[-1] )
    ax.set_yticklabels(short_name_tasks)
    ax.invert_yaxis()           # labels read top-to-bottom
    ax.set_xlabel(xlabel)
    ax.set_title(title)
    #
    ax.spines['right'].set_visible(False)
    ax.spines['top'].set_visible(False)
    ax.patch.set_facecolor('#FFFFFF')
    ax.spines['bottom'].set_color('#CCCCCC')
    ax.spines['bottom'].set_linewidth(1)
    ax.spines['left'].set_color('#CCCCCC')
    ax.spines['left'].set_linewidth(1)
    autolabel(a)

    fig.set_size_inches(w=13, h=0.5* top_n ,forward=True)
    plt.show()
    # plt.savefig(f'{title}.png')

def horizontal_bar_chart3(top_n, tasks, nums, nums2, xlabel='', ylabel='', title=''):
    print(title)
    df = pd.DataFrame(
        {'a':nums,'b':nums2},
        index=tasks
    )

    a_vals = df.a
    b_vals = df.b
    ind = np.arange(df.shape[0])
    width = 0.8    # bar width

    # Set the colors
    colors = ['b', 'g', 'r', 'c', 'm', 'y', 'g']

    def autolabel(bars):
        # attach some text labels
        for bar in bars:
            width = bar.get_width()
            ax.text(
                width + 40,
                bar.get_y() + bar.get_height() / 2,
                '%d' % int(width),
                ha='right',
                va='center'
            )
    # make the plots
    fig, ax = plt.subplots()
    a = ax.barh(ind, a_vals, width, color = colors) # plot a vals
    b = ax.barh(ind + width, b_vals, width, color = colors, alpha=0.5)  # plot b vals
    ax.set_yticks(ind + width)  # position axis ticks
    ax.set_yticklabels(df.index)  # set them to the names
    ax.legend((a[0], b[0]), ['a', 'b'], loc='center right')
    ax.invert_yaxis()  # invert order

    # autolabel(a)
    # autolabel(b)

    fig.set_size_inches(w=13, h=0.5* top_n,forward=True)
    plt.show()


def horizontal_bar_chart4(top_n, tasks, nums, nums2, xlabel='', ylabel='', title=''):
    def autolabel(bars):
        # attach some text labels
        for bar in bars:
            width = bar.get_width()
            ax.text(
                width*0.95, bar.get_y() + bar.get_height()/2,
                '%d' % int(width),
                ha='right',
                va='center'
            )

    df = pd.DataFrame(dict(
                        graph= tasks,
                        n= nums,
                        m= nums2
        ))

    ind = np.arange(len(df))
    width = 0.4         # 1.0 = 100%

    fig, ax = plt.subplots()
    a = ax.barh(ind, df.n, width, alpha=0.5, color='red', label='mean')
    b= ax.barh(ind + width, df.m, width, alpha=0.5, color='green', label='stddev')
    autolabel(a)
    autolabel(b)


    ax.set(yticks=ind + width, yticklabels=df.graph, ylim=[2*width - 1, len(df)])
    ax.legend()

    fig.set_size_inches(w=15, h=0.5* top_n, forward=True)
    ax.invert_yaxis()  # invert order

    plt.show()



def horizontal_bar_chart5(top_n, tasks, nums, nums2, xlabel='', ylabel='', title=''):
    def autolabel(bars):
        # attach some text labels
        for bar in bars:
            width = bar.get_width()
            ax.text(
                width*0.95, bar.get_y() + bar.get_height()/2,
                '%d' % int(width),
                ha='right',
                va='center'
            )

    df = pd.DataFrame(dict(
                        graph= tasks,
                        n= nums,
                        # m= nums2
        ))

    ind = np.arange(len(df))
    width = 0.4         # 1.0 = 100%

    fig, ax = plt.subplots()
    # p0 = ax.bar(range(len(self.qAvg)), self.qAvg, width, yerr=self.qStd)
    a = ax.barh(ind, df.n, width, xerr=nums2, alpha=0.5, color='red', label='mean')
    # b= ax.barh(ind + width, df.m, width, alpha=0.5, color='green', label='stddev')
    autolabel(a)
    # autolabel(b)


    ax.set(yticks=ind + width, yticklabels=df.graph, ylim=[2*width - 1, len(df)])
    ax.legend()

    fig.set_size_inches(w=15, h=0.5* top_n, forward=True)
    ax.invert_yaxis()  # invert order

    plt.show()


def horizontal_bar_chart6(top_n, tasks, nums, nums2, xlabel='', ylabel='', title=''):
    legends = 'test'
    fig, ax = plt.subplots()
    x_pos = [i for i, _ in enumerate(nums)]
    average = [None] * len(x_pos)
    variance = [None] * len(x_pos)

    for i in x_pos:
        average[i] = np.mean(nums)
        variance[i] = np.std(nums2)

    # print("[{}] Média: {} - ({})".format(title, average, np.average(average)))

    plt.barh(x_pos, average, color='steelblue', xerr=variance)

    plt.yticks(x_pos, tasks, fontsize=12)
    plt.xticks(list(range(11)), fontsize=12)

    plt.xlabel(xlabel)

    # plt.savefig(tasks + '_bar_err.png', bbox_inches='tight', dpi=400)
    fig.set_size_inches(w=15, h=0.5 * top_n, forward=True)
    plt.show()
    plt.close()


def horizontal_bar_chart7(top_n, tasks, nums, nums2, xlabel='', ylabel='', title=''):

    fig, ax = plt.subplots()

    ind = np.arange(len(tasks))
    plt.barh(ind, nums, color='steelblue', xerr=nums2)

    plt.yticks(ind, tasks, fontsize=12)
    plt.xticks(list(range(11)), fontsize=12)

    plt.xlabel(xlabel)

    fig.set_size_inches(w=15, h=0.5 * top_n, forward=True)
    ax.invert_yaxis()  # invert order
    ax.set_title(title)
    plt.show()
    # plt.savefig(tasks + '_bar_err.png', bbox_inches='tight', dpi=400)
    plt.close()



def horizontal_bar_chart_final(top_n, tasks, nums, nums2=[], xlabel='', ylabel='', title=''):
    mean= nums
    stddev = nums2


    # tip text
    # Set the colors
    print(title)
    colors = ['b', 'g', 'r', 'c', 'm', 'y', 'g']
    def autolabel(bars):
        # attach some text labels
        for bar in bars:
            width = bar.get_width()
            ax.text(width + 6, bar.get_y() + bar.get_height() / 2,
                    '%d' % int(width),
                    ha='right', va='center')
    #
    plt.rcdefaults()
    fig, ax = plt.subplots()

    # data
    y_pos = np.arange(len(mean))

    a= ax.barh(y_pos, mean, xerr=stddev,  align='center', color=colors, alpha=0.5)
    ax.set_yticks(y_pos)
    short_name_tasks = []
    for tsk in tasks:
        # short_name_tasks.append( tsk.split('::')[-1] )
        short_name_tasks.append( tsk )
    ax.set_yticklabels(short_name_tasks)
    ax.invert_yaxis()           # labels read top-to-bottom
    ax.set_xlabel(xlabel)
    ax.set_title(title)
    #
    ax.spines['right'].set_visible(False)
    ax.spines['top'].set_visible(False)
    ax.patch.set_facecolor('#FFFFFF')
    ax.spines['bottom'].set_color('#CCCCCC')
    ax.spines['bottom'].set_linewidth(1)
    ax.spines['left'].set_color('#CCCCCC')
    ax.spines['left'].set_linewidth(1)
    autolabel(a)

    fig.set_size_inches(w=16, h=0.5* top_n ,forward=True)
    plt.show()
    # plt.savefig(f'{title}.png')

def horizontal_bar_chart_final_single(top_n, tasks, nums, xlabel='', ylabel='', title=''):
    mean= nums


    # tip text
    # Set the colors
    print(title)
    colors = ['b', 'g', 'r', 'c', 'm', 'y', 'g']
    def autolabel(bars):
        # attach some text labels
        for bar in bars:
            width = bar.get_width()
            ax.text(width , bar.get_y() + bar.get_height() / 2,
                    '%d' % int(width),
                    ha='right', va='center')
    #
    plt.rcdefaults()
    fig, ax = plt.subplots()

    # data
    y_pos = np.arange(len(mean))

    a= ax.barh(y_pos, mean, align='center', color=colors, alpha=0.5)
    ax.set_yticks(y_pos)
    short_name_tasks = []
    for tsk in tasks:
        # short_name_tasks.append( tsk.split('::')[-1] )
        short_name_tasks.append( tsk )
    ax.set_yticklabels(short_name_tasks)
    ax.invert_yaxis()           # labels read top-to-bottom
    ax.set_xlabel(xlabel)
    ax.set_title(title)
    #
    ax.spines['right'].set_visible(False)
    ax.spines['top'].set_visible(False)
    ax.patch.set_facecolor('#FFFFFF')
    ax.spines['bottom'].set_color('#CCCCCC')
    ax.spines['bottom'].set_linewidth(1)
    ax.spines['left'].set_color('#CCCCCC')
    ax.spines['left'].set_linewidth(1)
    autolabel(a)

    fig.set_size_inches(w=16, h=0.5* top_n ,forward=True)
    plt.show()
    # plt.savefig(f'{title}.png')


if __name__ == '__main__':
    tasks = ['James Soong', 'Korea Fish', 'Tsai Ing-Wen']
    volumn = [608590, 5522119, 8170231]
    bar_char( volumn, tasks )
