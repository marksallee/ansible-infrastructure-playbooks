## LVM steps to create new disk, copy, then remove old vgs config
You have a huge disk in GCP that needs to be resized smaller. But you have to rebuild it and copy the data, since resize with LVM doesn't like going downward.

First, add a secondary smaller disk in gcp either in the GCP console or with gcloud.

Next, let's start setting up the temporary LVM disk to copy into:


```
sudo pvcreate /dev/sdd
sudo vgcreate vgdata2 /dev/sdd
sudo lvcreate -l +100%FREE -n lvdata2 vgdata2
sudo mkdir /tmp/data2
sudo mkfs.ext4 /dev/vgdata2/lvdata2
sudo mount -t ext4 /dev/vgdata2/lvdata2 /tmp/data2
sudo systemctl stop postgresql-15
```

### Copy the data over  
```
sudo rsync -aCpogr /data/ /tmp/data2/ --progress

Example with Linux "parallel" utility to make it faster:

sudo find /data/ -mindepth 1 -maxdepth 1 | parallel -j 4 sudo rsync -asCpogr {} /tmp/data2/
```

### Start removing the too-large disk:  
```
sudo umount /data
sudo lvchange -an /dev/vgdata1/lvdata1
sudo lvremove /dev/vgdata1/lvdata1
sudo vgremove vgdata1
sudo pvremove /dev/sdc
sudo vgrename vgdata2 vgdata1
```

### Rename new lvdata2 back to lvdata1  
```
sudo lvrename vgdata1 lvdata2 lvdata1
sudo mount -a

then reboot: sudo shutdown -rf now
```
When confirmed, you can delete the too-large disk that is no longer associated with the VM.  

### The VM should come back up with the new disk assigned correctly.  
