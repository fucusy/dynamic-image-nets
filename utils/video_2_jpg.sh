#!/bin/bash
cur_dir=`pwd`
source_video_path=~/Downloads/UCF-101

echo "current dir is $cur_dir"


for dir in $source_video_path/*
do
	for sub_video in $dir/*.avi
	do
		echo "process $sub_video now"
		input=$sub_video
		s=${sub_video##*/}
		output_dir=${s%.*}
		mkdir -p $output_dir
		ffmpeg -i $input -r 10 $output_dir/%05d.jpg
		for img in $output_dir/*.jpg
		do
			ffmpeg -i $img -vf scale=256:256 $img -y
		done
	done
done

echo "done all work"
