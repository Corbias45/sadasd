#!/usr/bin/env bash
# Author: Mayank Kumar (@mac_editor on egpu.io)
# Format an external disk and install automate-eGPU-EFI (v1.0.5)

clear

# Text configuration
shopt -s nocasematch
bold="$(tput bold)"
normal="$(tput sgr0)"

# Environment
pb="/usr/libexec/PlistBuddy"
disk_plist=".disks.plist"
partition_names=()
partition_ids=()

echo -e ">> ${bold}Automate eGPU EFI 1.0.5 Installer${normal}\n"

# Phase 1: Disk Management
echo -e "> ${bold}Phase 1${normal}: Disk Management\n"
diskutil list -plist external > "${disk_plist}"
whole_disk_count=$($pb -c "Print :WholeDisks" "${disk_plist}" | sed -e 1d -e '$d' | wc -w)
if (( $whole_disk_count == 0 ))
then
  echo -e "No external disks detected. Please connect an external disk."
  echo -e "Internal disks are not supported for safety reasons.\n"
  rm "${disk_plist}"
  exit
fi
for (( i = 0; i < ${whole_disk_count}; i++ ))
do
  base_cmd="Print :AllDisksAndPartitions:${i}:Partitions"
  partition_count=$($pb -c "${base_cmd}" "${disk_plist}" | sed -e 1d -e '$d' | grep -o -i "Dict" | wc -l)
  for (( j = 0; j < ${partition_count}; j++ ))
  do
    partition_content="$($pb -c "${base_cmd}:${j}:Content" "${disk_plist}")"
    if [[ "${partition_content}" == "EFI" ]]
    then
      continue
    fi
    partition_name="$($pb -c "${base_cmd}:${j}:VolumeName" "${disk_plist}")"
    partition_id="$($pb -c "${base_cmd}:${j}:DeviceIdentifier" "${disk_plist}")"
    partition_names+=("${partition_name}")
    partition_ids+=("${partition_id}")
  done
done
for (( i = 0; i < ${#partition_names[@]}; i++ ))
do
  disk_no=$(( $i + 1 ))
  echo -e "  ${bold}${disk_no}${normal}. ${partition_names[$i]}"
done
echo -e "\n  ${bold}0${normal}. Quit"
echo -e "\nChoose a disk to format. All data on that disk will be lost.\n"
input=""
read -n1 -p "${bold}Disk #${normal}: " input
echo
if [[ -z "${input}" ]] || (( $input < 1 || $input > ${#partition_names[@]} ))
then
  echo -e "\nAborting.\n"
  rm ${disk_plist}
  exit
fi
input=$(( $input - 1 ))
echo -e "\n${bold}Selected Disk${normal}: ${partition_names[${input}]} (/dev/${partition_ids[${input}]})"
echo -e "\nIf you proceed, the selected disk will be erased.\n"
proceed="N"
read -n1 -p "${bold}Proceed?${normal} [Y/N]: " proceed
echo
if [[ "${proceed}" != "Y" ]]
then
  echo -e "\nAborting.\n"
  exit
fi
echo -e "\n${bold}Erasing disk...${normal}"
diskutil eraseVolume FAT32 EGPUBOOT "${partition_ids[${input}]}" 2>/dev/null 1>/dev/null
target_dir="/Volumes/EGPUBOOT"
if [[ ! -e "${target_dir}" ]]
then
  echo -e "Erasure failed. Aborting.\n"
  exit
fi
echo -e "Disk erased.\n"
rm .disks.plist

# Phase 2: Disk Management
echo -e "> ${bold}Phase 2${normal}: EFI Installation\n"
echo -e "${bold}Retrieving...${normal}"
curl -L -s -o "${target_dir}/EFI.zip" "https://egpu.io/wp-content/uploads/2018/10/EFI.zip"
exp_integrity="75cea4616bc74d2fab8179251ec15f6e773dc4cc9f7f858d4cdb473db241797131e40a5bce1114f214ef4b98cc731d9e2e5600338189916cbac2dd40c277b869"
file_integrity=$(shasum -a 512 -b "${target_dir}/EFI.zip" | awk '{ print $1 }')
if [[ "${file_integrity}" != "${exp_integrity}" ]]
then
  echo -e "Download failed or invalid file.\n"
  rm "${target_dir}/EFI.zip"
  exit
fi
echo "Files retrieved."
echo "${bold}Setting up disk...${normal}"
unzip -d "${target_dir}" "${target_dir}/EFI.zip" 1>/dev/null 2>&1
rm "${target_dir}/EFI.zip"
if [[ ! -d "${target_dir}/EFI" ]]
then
  echo -e "Unable to set up disk. Aborting.\n"
  exit
fi
rm -rf "${target_dir}/__MACOSX"
echo -e "Setup complete.\n"

# Phase 3: Patch Selection
echo -e "> ${bold}Phase 3${normal}: Patch Selection\n"
tb_type="$(ioreg | grep AppleThunderboltNHIType)"
tb_type="${tb_type##*+-o AppleThunderboltNHIType}"
tb_type="${tb_type::1}"
echo -e "Specify which eGPU vendor you are using for optimized patches.\n"
echo -e "${bold}1${normal}. NVIDIA\n${bold}2${normal}. AMD\n"
read -n1 -p "${bold}Vendor${normal}: " input
echo
if [[ -z "${input}" ]] || (( $input < 1 || $input > 2 ))
then
  echo -e "\nInvalid input. Aborting.\n"
  exit
fi
if (( $input == 1 ))
then
  echo -e "\n${bold}EFI ready to go.${normal}\n"
  exit
fi
echo -e "\n${bold}Updating configuration...${normal}"
config_plist="${target_dir}/EFI/CLOVER/config.plist"
$pb -c "Delete :KernelAndKextPatches:KextsToPatch:0" "${config_plist}"
$pb -c "Set :KernelAndKextPatches:KextsToPatch:0:Comment \"AppleGPUWrangler Thunderbolt Patch © egpu.io [mac_editor]\"" "${config_plist}"
patch_data_find="IOThunderboltSwitchType3"
patch_data_replace="IOThunderboltSwitchType${tb_type}"
$pb -c "Set :KernelAndKextPatches:KextsToPatch:0:Find ${patch_data_find}" "${config_plist}"
$pb -c "Set :KernelAndKextPatches:KextsToPatch:0:Replace ${patch_data_replace}" "${config_plist}"
$pb -c "Delete :SystemParameters:NvidiaWeb" "${config_plist}"
echo "Configuration updated."
echo -e "\n${bold}EFI ready to go.${normal}\n"