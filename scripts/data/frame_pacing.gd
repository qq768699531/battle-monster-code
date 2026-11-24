extends RefCounted
class_name FramePacing
## 原生主循环的固定帧间隔。原生不是「按 delta 自由推进」，而是每帧睡一个固定间隔，
## 再把 `ThreadData.elapsed_frame_milliseconds` 赋成它（`EFC_thrPLAY:3-5`）；
## 所有「按帧推进」的表现都以这个间隔为单位。
##
## 档位由 `EFC_thrSPEED` 写：0→120、1→100、2→80、3→60、4→50（ms），
## `EFC_thrInitialize:14` 选档 4，所以**默认为 50 ms（20 fps）**。
## 速度设置（档位 0–4）工程尚未实现，按帧折算一律用默认档的值。

## 一帧的时长（秒）。事件记录（`Evt_stdPROC` 的 `step_count`）与地图推进、
## 小地图滑动等都按帧计数，折成秒时乘它；不要按 60 fps 折算（见 `wiki\ui\frame-pacing.md`）。
const NATIVE_FRAME_SECONDS := 0.05


## 把原生帧数折成秒。
static func seconds_of_frames(frames: int) -> float:
	return NATIVE_FRAME_SECONDS * float(frames)
