from enum import IntEnum
class Status(IntEnum):
    OK = 0
    NO_CREDIT_HISTORY = 1
    NO_RUNNING_CLUSTER = 2
    NO_AVAILABLE_STACK = 3
    NO_STACK = 4
    STACK_NOT_FOUND = 5
    S3_BUCKET_NOT_EXIST = 6
    STACK_ERROR = 7
    CLUSTER_ERROR = 8
    USER_NOT_FOUND = 9
    AUTH_ERROR = 10