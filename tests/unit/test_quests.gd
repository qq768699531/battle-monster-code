extends "res://tests/unit/gut_case.gd"


func test_legacy_suite() -> void:
	var table: QuestTable = QuestSet.load_table()
	assert_gt(table.size(), 0, "任务表非空")
	# 任务 43（NPC 30）的两个前置都是「必须已完成」，分别指向任务 39／40（`Qst_stdCHECK` 的
	# `v11[6] == 2` 分支），另要求累计进度 5。
	var record := table.record(43)
	assert_eq([record.get("prereq_kind"), record.get("prereq_quest"),
		record.get("prereq2_kind"), record.get("prereq2_quest"), record.get("goal_count")],
		[2, 39, 2, 40, 5], "任务 43 的前置与目标数量")
	# 越界返回空表，并按外部边界集中校验的要求报错。
	var missing := table.record(9999)
	assert_push_error("不在表内")
	assert_eq(missing, {}, "越界任务号返回空表")
