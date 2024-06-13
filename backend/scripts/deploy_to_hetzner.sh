#! /bin/bash -e
# Usage: ./scripts/deploy_dev.sh dev(production) deploy(setup/stop/restart)

#prerquirre: /btc/apps/satosea-runes-data dir has permitsion; /btc/apps/satosea-runes-data/reserve/.env and other files exists


#server=10.0.0.7

local_root_dir=`pwd`
local_tmp_dir=${local_root_dir}/tmp

deploy_root_dir=/btc/apps/satosea-mempool
deploy_release_dir=${deploy_root_dir}/release
deploy_current_dir=${deploy_root_dir}/current

#for shared files, like log or env
reserve_dir=${deploy_root_dir}/reserve
reserve_log_dir=${reserve_dir}/log
reserve_cache_dir=${reserve_dir}/cache
reserve_config_file=${reserve_dir}/mempool-config.json

app_code_name=mempool
release_file=`date +%Y%m%d%H%M%S`
local_app_dir=${local_tmp_dir}/${release_file}
upload_release_file=${release_file}.tar.gz

release_keep=10

branch=$1
action=$2

function set_env()
{
  echo set env
  client_env=production
  case $branch in
    dev)
      user_name=root
      server=46.4.92.92
      #node_dev=development
      ;;
    production)
      user_name=root
      # server=162.55.87.116
      server=5.9.208.174
      ;;
    *)
      echo "branch $branch not valid"
      echo $usage
      exit 0
      ;;
  esac
  echo branch: $branch
  echo server: $server
}

function prepare_reserve_files()
{
  echo
  echo remote prepare reserve files
  echo first time must create user permissioned $deploy_root_dir on $server, and prepare files !!!
  ssh ${user_name}@${server} "mkdir -p ${deploy_release_dir};mkdir -p ${reserve_log_dir};mkdir -p ${reserve_cache_dir};"
}

function prepare_app()
{
    echo
    echo prepare app

    mkdir -p ${local_tmp_dir}/${app_code_name}

    rsync -a --exclude 'tmp' --exclude 'temp' --exclude 'log' --exclude 'cache' --exclude 'node_modules' --exclude ".*" --exclude mempool-config.json ${local_root_dir} ${local_tmp_dir}/${app_code_name}
    # rsync rust folder of parent 
    rsync -a ${local_root_dir}/../rust ${local_tmp_dir}/${app_code_name}

    mv ${local_tmp_dir}/${app_code_name} $local_app_dir
}

function tar_deploy_file()
{
  echo
  echo tar deploy file
  cd $local_tmp_dir
  ls -l
  echo $upload_release_file
  echo ${release_file}
  tar -zcf $upload_release_file ${release_file}
  rm -r $local_app_dir
  cd $local_root_dir
}

function rsync_deploy_file_to_server() {
  echo
  echo rsync deploy file to server
  rsync -a ${local_tmp_dir}/${upload_release_file} ${user_name}@${server}:${deploy_release_dir}

  rm ${local_tmp_dir}/${upload_release_file}
}

function extract_remote_deploy_file()
{
  echo
  echo extract remote deploy file
  ssh ${user_name}@${server} "cd ${deploy_release_dir}; tar -zxf ${upload_release_file}; ls -lh ${upload_release_file}; cd ${release_file}/backend; ln -s ${reserve_log_dir} log; ln -s ${reserve_cache_dir} cache; ln -s ${reserve_config_file} mempool-config.json;"
}

function npm_install_and_build()
{
  echo
  echo remote npm install and build
  ssh ${user_name}@${server} "source /root/.nvm/nvm.sh; nvm use 20.11.0; source /root/.cargo/env; cd ${deploy_release_dir}/${release_file}/backend; npm install --no-install-links; npm run build"
}

function link_current()
{
  echo
  echo link current
  ssh ${user_name}@${server} "rm $deploy_current_dir; ln -s ${deploy_release_dir}/${release_file} $deploy_current_dir"
}

function set_revision()
{
  if [ "$(which git)" ]
  then
    local local_commit=$(git rev-parse HEAD)
  fi
  local real_commit=${CI_COMMIT_SHA:-$local_commit}
  ssh ${user_name}@${server} "echo ${real_commit} > ${deploy_current_dir}/REVISION"
}

function clean_old_releases()
{
  echo
  echo clean old releases
  ssh ${user_name}@${server} "cd $deploy_release_dir; count=\`ls -t | wc -w\`;  if [ \$count -gt $release_keep ]; then echo has old releases and clean && clean_num=\`expr \$count - $release_keep\` && ls -1tr | head -n \$clean_num | xargs rm -r ; else echo no releases to clean; fi"
}

function stop_nest_server() {
    echo
    echo stop nestjs
    ssh ${user_name}@${server} "source /root/.nvm/nvm.sh; sudo systemctl stop satosea-mempool"
}

function restart_nest_server() {
    echo
    echo restart nestjs
    ssh ${user_name}@${server} "source /root/.nvm/nvm.sh; sudo systemctl restart satosea-mempool"
}

set_env

case $action in
  setup)
    prepare_reserve_files
    ;;
  deploy)
    prepare_app
    tar_deploy_file
    rsync_deploy_file_to_server
    extract_remote_deploy_file
    npm_install_and_build
    link_current
    set_revision
    sleep 5
    restart_nest_server
    clean_old_releases
    ;;
  stop)
    stop_nest_server
    ;;
  restart)
    restart_nest_server
    ;;
  *)
    echo "action $action not valid"
    echo $usage
    exit 1
    ;;
esac

