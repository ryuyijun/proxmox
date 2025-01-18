#!/bin/bash

# Proxmox 환경 확인 함수
check_proxmox_environment() {
    if [ -f /etc/pve/pve.version ] || command -v pvesh &> /dev/null; then
        echo "Proxmox Environment detected"
    else
        echo "This environment is not Proxmox"
        exit 1
    fi
}

# 필요한 패키지 확인 및 설치
install_package() {
    local package=$1
    if ! dpkg -l | grep -q "^ii  $package "; then
        echo "$package 패키지가 설치되어 있지 않습니다. 설치를 진행합니다..."
        apt-get update -y > /dev/null 2>&1
        apt-get install -y $package > /dev/null 2>&1
        echo "$package 패키지 설치가 완료되었습니다."
    else
        echo "$package 패키지가 이미 설치되어 있습니다."
    fi
}

# 이미지 파일 다운로드 및 압축 해제 함수
download_and_extract_image() {
    local url=$1
    local zip_path=$2
    local img_path=$3
    wget $url -O $zip_path
    if [[ $zip_path == *.zip ]]; then
        unzip -o $zip_path -d $(dirname $img_path)
        mv $(dirname $img_path)/$(basename $zip_path .zip).img $img_path
    elif [[ $zip_path == *.gz ]]; then
        gunzip -f $zip_path
    fi
}

# 이미지 파일 확인 및 다운로드 함수
check_and_download_image() {
    local img_name=$1
    local img_url=$2
    local img_path=$3
    
    if [ -f "$img_path" ]; then
        read -p "$img_name 이미지가 이미 존재합니다. 재다운로드하시겠습니까? (y/n): " choice
        if [ "$choice" = "y" ]; then
            download_and_extract_image $img_url $img_path.gz $img_path
        fi
    else
        echo "$img_name 이미지가 존재하지 않습니다. 다운로드를 시작합니다..."
        download_and_extract_image $img_url $img_path.gz $img_path
    fi
}

# 디스크 추가 함수
add_disk() {
    local DISK_TYPE=$1
    local STORAGE_NAME=$2
    local DISK_SIZE=$3
    local DISK_INDEX=$4

    if [ "$DISK_TYPE" == "sata" ]; then
        qm set $VMID --sata${DISK_INDEX} $STORAGE_NAME:$DISK_SIZE
    elif [ "$DISK_TYPE" == "scsi" ]; then
        qm set $VMID --scsihw virtio-scsi-single --scsi${DISK_INDEX} $STORAGE_NAME:$DISK_SIZE
    fi
}

# 디스크 타입 검증 함수
validate_disk_type() {
    local DISK_TYPE=$1
    if [ "$DISK_TYPE" != "sata" ] && [ "$DISK_TYPE" != "scsi" ]; then
        echo "잘못된 디스크 타입입니다. sata 또는 scsi를 입력해 주세요."
        return 1
    fi
    return 0
}

# 디스크 수 검증 함수
validate_disk_count() {
    local COUNT=$1
    if [[ ! "$COUNT" =~ ^[1-9]$ ]]; then
        echo "디스크 수는 1부터 9까지의 숫자여야 합니다."
        return 1
    fi
    return 0
}

# Proxmox 환경 확인
check_proxmox_environment

# jq 및 unzip 패키지 설치 확인
install_package "jq"
install_package "unzip"

# 이미지 파일 확인 및 다운로드
check_and_download_image "m-shell" "https://github.com/PeterSuh-Q3/tinycore-redpill/releases/download/v1.1.0.1/tinycore-redpill.v1.1.0.1.m-shell.img.gz" "/var/lib/vz/template/iso/m-shell.img"
check_and_download_image "RR" "https://github.com/RROrg/rr/releases/download/25.1.0/rr-25.1.0.img.zip" "/var/lib/vz/template/iso/rr.img"
check_and_download_image "xTCRP" "https://github.com/PeterSuh-Q3/tinycore-redpill/releases/download/v1.1.0.1/tinycore-redpill.v1.1.0.1.xtcrp.img.gz" "/var/lib/vz/template/iso/xtcrp.img"

# 사용자 입력 받기
read -p "VM 번호를 입력하세요 (숫자): " VMID
read -p "VM 이름을 입력하세요 : " VMNAME
read -p "CPU 코어 수를 입력하세요 : " CORES
read -p "RAM 크기를 MB 단위로 입력하세요 (ex)4096=4G: " RAM

# 현재 노드 이름 가져오기
NODE=$(hostname)

# Proxmox에서 현재 노드의 스토리지 목록 가져오기
echo "현재 노드에서 사용 가능한 스토리지 목록 및 용량:"
pvesh get /nodes/$NODE/storage

# 디스크 수 입력 받기
while true; do
    read -p "사용할 디스크 수를 입력하세요: " DISK_COUNT
    if validate_disk_count $DISK_COUNT; then
        break
    fi
done

# 디스크 정보 입력 받기 및 추가
declare -a DISK_ARRAY
for (( i=0; i<$DISK_COUNT; i++ ))
do
    echo "디스크 $((i+1)) 설정:"
    while true; do
        read -p "디스크 타입을 입력하세요 (sata 또는 scsi): " DISK_TYPE
        if validate_disk_type $DISK_TYPE; then
            break
        fi
    done
    read -p "스토리지 이름을 입력하세요 (ex. local-LVM): " STORAGE_NAME
    read -p "디스크 크기를 GB 단위로 입력하세요: " DISK_SIZE
    DISK_ARRAY+=("$DISK_TYPE $STORAGE_NAME $DISK_SIZE")
done

# 네트워크 브릿지 목록 출력
echo "사용 가능한 네트워크 브릿지 목록 :"
pvesh get /nodes/$NODE/network

# 네트워크 브릿지 입력 받기
read -p "사용할 네트워크 브릿지 이름을 입력하세요 (ex. vmbr0) : " NET_BRIDGE

# 이미지 파일 선택
echo "사용할 이미지 파일을 선택하세요:"
echo "1. m-shell (m-shell.img)"
echo "2. RR (rr.img)"
echo "3. xTCRP (xtcrp.img)"
read -p "선택 (1 - 3): " IMAGE_CHOICE

# 이미지 파일 경로 설정
if [ "$IMAGE_CHOICE" -eq 1 ]; then
    IMG_PATH="/var/lib/vz/template/iso/m-shell.img"
elif [ "$IMAGE_CHOICE" -eq 2 ]; then
    IMG_PATH="/var/lib/vz/template/iso/rr.img"
elif [ "$IMAGE_CHOICE" -eq 3 ]; then
    IMG_PATH="/var/lib/vz/template/iso/xtcrp.img"
else
    echo "잘못된 선택입니다. 1 부터 3까지의 숫자를 입력하세요."
    exit 1
fi

# VM 생성
qm create $VMID --name $VMNAME --memory $RAM --cores $CORES --net0 virtio,bridge=$NET_BRIDGE --bios seabios --ostype l26

# 디스크 추가
for (( i=0; i<$DISK_COUNT; i++ ))
do
    DISK_INFO=(${DISK_ARRAY[$i]})
    add_disk ${DISK_INFO[0]} ${DISK_INFO[1]} ${DISK_INFO[2]} $i
done

# 부팅 순서 설정 (net0 우선)
qm set $VMID --boot order=net0

# 커스텀 args 추가
qm set $VMID --args "-drive 'if=none,id=synoboot,format=raw,file=$IMG_PATH' -device 'qemu-xhci,addr=0x18' -device 'usb-storage,drive=synoboot,bootindex=5'"

# 요약 정보 출력
echo "-----------------------------------------------------"
echo "VM 생성이 완료되었습니다!"
echo "VM ID: $VMID"
echo "VM 이름: $VMNAME"
echo "CPU 코어 수: $CORES"
echo "RAM 크기: $RAM MB"
echo "네트워크 브릿지: $NET_BRIDGE"
echo "이미지 파일: $IMG_PATH"
echo "디스크 수: $DISK_COUNT"

for (( i=0; i<$DISK_COUNT; i++ ))
do
    DISK_INFO=(${DISK_ARRAY[$i]})
    echo "디스크 $((i+1)) - 타입: ${DISK_INFO[0]}, 스토리지: ${DISK_INFO[1]}, 크기: ${DISK_INFO[2]} GB"
done

# VM 실행 여부 확인
read -p "VM을 지금 실행하시겠습니까? (y/n): " START_VM
if [[ $START_VM == "y" || $START_VM == "Y" ]]; then
    echo "VM을 시작합니다..."
    qm start $VMID
    echo "VM이 성공적으로 시작되었습니다!"
else
    echo "VM이 생성되었지만 시작되지 않았습니다. 나중에 수동으로 시작할 수 있습니다."
fi

echo "스크립트 실행이 완료되었습니다."
