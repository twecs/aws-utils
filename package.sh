# AWS_PROFILE=personal sh -- .../package.sh .../twecs/wise twecs-repository-bucket-1st5bpn5y8a3q 3.8


set -e

source_directory="$1"
deployment_bucket="$2"

shift
shift

git_commit_id="$(
	git \
		-C "${source_directory}" \
		rev-parse \
		HEAD \
		#
)"

python_package_name="$(
	python \
		-- \
		"${source_directory}/setup.py" \
		--name \
		#
)"

output_directory="$(
	mktemp \
		--directory \
		--tmpdir \
		-- \
		"aws.lambda.python-${python_package_name}-XXXXXXXXXX" \
		#
)"

for python_version in "$@"
do
	container_id="$(
		docker \
			run \
			--interactive \
			--tty \
			--detach \
			-- \
			"public.ecr.aws/sam/build-python${python_version}" \
			/bin/sh \
			#
	)"

	docker \
		cp \
		-- \
		"${source_directory}" \
		"${container_id}:/var/task/source" \
		#

	docker \
		exec \
		--workdir /var/task/source \
		-- \
		"${container_id}" \
		python \
		-- \
		setup.py \
		bdist_wheel \
		#

	docker \
		exec \
		-- \
		"${container_id}" \
		sh \
		-c \
		"pip install --target /var/task/output/python/lib/python${python_version}/site-packages/ /var/task/source/dist/*.whl" \
		#

	docker \
		cp \
		-- \
		"${container_id}:/var/task/output/." \
		"${output_directory}/package" \
		#

	docker \
		rm \
		--force \
		-- \
		"${container_id}"
done

deployment_package_file_path="${output_directory}/${git_commit_id}.zip"

cd \
	"${output_directory}/package" \
	#

zip \
	--quiet \
	--recurse-paths \
	-9 \
	"${deployment_package_file_path}" \
	-- \
	. \
	#

deployment_object_key="${python_package_name}/${git_commit_id}.zip"

mime_type="$(
	file \
		--brief \
		--mime-type \
		-- \
		"${deployment_package_file_path}" \
		#
)"

if [[ ${upload} == yes || ! -v upload ]]
then
	aws \
		s3api \
		put-object \
		--bucket "${deployment_bucket}" \
		--key "${deployment_object_key}" \
		--body "${deployment_package_file_path}" \
		--content-type "${mime_type}" \
		#
fi

if [[ ${cleanup} == yes || ! -v cleanup ]]
then
	rm \
		--force \
		--recursive \
		-- \
		"${output_directory}" \
		#
fi

if [[ -v key_file_path ]]
then
	echo \
		-n \
		"${deployment_object_key}" \
		> "${key_file_path}" \
		#
else
	echo \
		"${deployment_object_key}" \
		#
fi
