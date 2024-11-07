from math import exp

UNIT = 1e18
GOAL_PER_UNIT = 5e16

SECONDS_PER_WEEK = 604800

current_per_sec = 0
increase_per_sec = 1e2
result = 0
while(result < GOAL_PER_UNIT):
    current_per_sec += increase_per_sec
    result = UNIT * current_per_sec * 52 * SECONDS_PER_WEEK / UNIT

print("FOUND LINEAR", current_per_sec)
print("RESULT FROM LINEAR", result)

FROM_COMPOUND = ((1e18 * exp(0.05 * 1) - 1e18) / 365 / 24 / 60 / 60)
RESULT_FROM_COMPOUND_CLAIMED_EACH_WEEK = UNIT * FROM_COMPOUND * 52 * SECONDS_PER_WEEK / UNIT

print("FROM_COMPOUND", FROM_COMPOUND)
print("RESULT_FROM_COMPOUND_CLAIMED_EACH_WEEK", RESULT_FROM_COMPOUND_CLAIMED_EACH_WEEK)

print("ratio of compound / linear", FROM_COMPOUND / current_per_sec)