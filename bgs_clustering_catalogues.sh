###################################################################################
#BGS CLUSTERING CATALOGUES 

#Instructions for generating clustering and random catalogues for the BGS using the 
#`mkCat_main.py` script, starting from the `full_HPmapcut` catalogues produced by Ashley.

#This script will do the following:
#1) create a clustering catalogue for the BGS_BRIGHT sample
#2) create a clustering catalogue for the BGS_BRIGHT-21.5 cosmology sample, 
#   with imaging systematic weights
#3) create a clustering catalogue for BGS volume-limited samples with different 
#   absolute magnitude cuts, with imaging systematic weights

#To run this script, on the command line enter:
#./clustering_catalogues.sh
#You might need to first change the permissions by doing
#chmod 755 clustering_catalogues.sh

#Set the number of random files to use
export NUM_RAND=1
#If you are re-running this script, delete existing outputs and cloned github repositories
export DELETE_OLD=true
#Catalogue version to use. v1.4pip is latest version with PIP weights
export VERSION=v1.4pip

#First, load the DESI environment.
source /global/common/software/desi/users/adematti/cosmodesi_environment.sh main

#Create a new directory `desi` in your scratch space, and clone the LSS repo here. 
#If DELETE_OLD is set to true, delete any existing outputs and repositories
#My branch of the repo has a modified version of mkCat_main.py with extra arguments
#that allow different z and magnitude cuts
#Using a different directory name here is fine, and none of the lines below will be affected.
export LSS_DIR=$SCRATCH/desi_TEST

export CAT_DIR=Y1/LSS/iron/LSScats #directory structure of the LSS catalogue

if [ $DELETE_OLD ]
then
  rm -rf $LSS_DIR/$CAT_DIR/$VERSION
  rm -rf $LSS_DIR/LSS
  rm -rf $LSS_DIR/hodpy
fi

mkdir -p $LSS_DIR
cd $LSS_DIR
#git clone https://github.com/desihub/LSS.git
git clone https://github.com/amjsmith/LSS.git

#Make a directory to store the clustering and random catalogues, with the 
#right directory structure expected by `mkCat_main.py`
export OUTPUT_DIR=$LSS_DIR/$CAT_DIR/$VERSION
mkdir -p $OUTPUT_DIR/hpmaps

#Copy the `full_HPmapcut` files that are needed, for data and randoms. 
#This copies 4 of the 18 random files, but a different number can be used if needed.
#v1.4pip is the most up to date version, which includes BITWEIGHTS
#Need to copy healpix maps from the v1.3 directory (they don't exist in v1.4pip directory, but haven't changed from v1.3)
export DATA_DIR=/global/cfs/cdirs/desi/survey/catalogs/$CAT_DIR/$VERSION
cp -f $DATA_DIR/BGS_BRIGHT_full_HPmapcut.dat.fits $OUTPUT_DIR
if [ $NUM_RAND -lt 10 ]
then
  cp -f $DATA_DIR/BGS_BRIGHT_[0-$NUM_RAND]_full_HPmapcut.ran.fits $OUTPUT_DIR
else
  cp -f $DATA_DIR/BGS_BRIGHT_*_full_HPmapcut.ran.fits $OUTPUT_DIR
fi
cp -f $DATA_DIR/BGS_BRIGHT_frac_tlobs.fits $OUTPUT_DIR
#cp -f $DATA_DIR/hpmaps/BGS* $OUTPUT_DIR/hpmaps/
cp -f /global/cfs/cdirs/desi/survey/catalogs/Y1/LSS/iron/LSScats/v1.3/hpmaps/BGS* $OUTPUT_DIR/hpmaps/

#Copy the regular `full` files without the HPmapcut, if needed
#cp $DATA_DIR/BGS_BRIGHT_full.dat.fits $OUTPUT_DIR
#cp $DATA_DIR/BGS_BRIGHT_[0-3]_full.ran.fits $OUTPUT_DIR

#Finally, run the `mkCat_main.py` script to generate the catalogues. This will generate the 
#file `$OUTPUT_DIR/BGS_BRIGHT_clustering.dat.fits`, with similar random files.
#`--clusd y` - set to `y` to make the clustering catalogue 
#`--clusran y` - set to `y` to make the random catalogue(s)
#`--minr 0` - first random file is set to file number `0`
#`--maxr 4` - last random file is set to file number `0`. Increase this if more randoms are used
#`--bgs_zmin -0.0033` - Minimum redshift limit (default is 0.01)
#`--bgs_zmax 1.0` - Maximum redshift limit (default is 0.5)
#`--splitGC y` - Creates NGC and SGC files, which are needed when calculating the clustering
#`--compmd altmtl` - This argument is recommended for bitweights
#`--nz y` - This is needed to refactor the weights
#`--splitGC y` - Create output files split into NGC and SGC. This is needed if you want to run xirunpc.py
#By default it uses the `full_HPmapcut` files
#To use the `full` files instead, include (with the empty string) --use_map_veto ''
export PYTHONPATH=$LSS_DIR/LSS/py:$PYTHONPATH
export SCRIPT_DIR=$LSS_DIR/LSS/scripts/main
python $SCRIPT_DIR/mkCat_main.py --basedir $LSS_DIR --type BGS_BRIGHT --survey Y1 --verspec iron --version $VERSION --clusd y --clusran y --minr 0 --maxr $NUM_RAND --compmd altmtl --bgs_zmin -0.0033 --bgs_zmax 1.0 --splitGC y --nz y #--use_map_veto ''


#The files produced contain the fluxes in different bands, but not magnitudes. 
#Run Sam's k-correction code to get rest-frame g-r colours and absolute r-band magnitudes
#This adds columns of `ABSMAG_R` and `REST_GMR_0P1`
git clone -b abacus https://github.com/amjsmith/hodpy.git
export PYTHONPATH=$LSS_DIR/hodpy:$PYTHONPATH

declare -a region=("" "NGC_" "SGC_")

NUM_RAND_LOOP=`expr $NRAN - 1` #subtract 1 from NUM_RAND, for the for loop
for r in "${region[@]}"
do
  python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT_${r}clustering.dat.fits
  for i in `seq 0 $NUM_RAND_LOOP`
  do 
    python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT_${r}${i}_clustering.ran.fits
  done
done


###################################################################################
#CLUSTERING CATALOGUES WITH IMAGING SYSTEMATIC WEIGHTS FOR BGS_BRIGHT-21.5 COSMOLOGY SAMPLE

#Need to add magnitudes to the `full_HPmapcut` file for cutting to volume-limited samples
python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT_full_HPmapcut.dat.fits

#-21.5 cosmology sample with linear regression systematic weights
#`--imsys y` - add imaging systematic weights
#`--imsys_zbin y` - do imaging systamtic regressions in z bins
#`--absmagmd phot` - cut to the sample using the magnitudes with Sam's k-corrections, added above 
#`--imsys_colname WEIGHT_IMLIN` - convert linear regression weights to WEIGHT_SYS in the final files
python $SCRIPT_DIR/mkCat_main.py --basedir $LSS_DIR --type BGS_BRIGHT-21.5 --fulld n --imsys y --survey Y1 --verspec iron --imsys_zbin y --version $VERSION --use_map_veto _HPmapcut --clusd y --clusran y --minr 0 --maxr $NUM_RAND --compmd altmtl --absmagmd phot --imsys_colname WEIGHT_IMLIN --splitGC y --nz y

# Add the magnitudes and colours to the clustering catalogues and randoms
NUM_RAND_LOOP=`expr $NRAN - 1` #subtract 1 from NUM_RAND, for the for loop
for r in "${region[@]}"
do
  python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT-21.5_${r}clustering.dat.fits
  for i in `seq 0 $NUM_RAND_LOOPD`
  do 
    python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT-21.5_${r}${i}_clustering.ran.fits
  done
done

# Move to a new directory to make sure they aren't overwritten in the next part
mkdir $OUTPUT_DIR/BGS_BRIGHT-21.5
mv $OUTPUT_DIR/BGS_BRIGHT-21.5_* $OUTPUT_DIR/BGS_BRIGHT-21.5/


###################################################################################
#CLUSTERING CATALOGUES WITH IMAGING SYSTEMATIC WEIGHTS FOR MAGNITUDE THRESHOLD SAMPLES

#set the magnitude and redshift limits for each sample
declare -a magnitude=(-22.0 -21.5 -21.0 -20.5 -20.0  -19.5 -19.0  -18.5   -18.0 -17.5  -17.0)
declare -a      zmax=(  0.3   0.3   0.3   0.3   0.25   0.2   0.15   0.125   0.1   0.08   0.07)

#loop through each sample
#be careful because the output files still get called `BGS_BRIGHT-21.5` even though the
#magnitude and redshift limits are changed
NUM_RAND_LOOP=`expr $NRAN - 1` #subtract 1 from NUM_RAND, for the for loop
for m in `seq 0 1`
do 
  python $SCRIPT_DIR/mkCat_main.py --basedir $LSS_DIR --type BGS_BRIGHT-21.5 --fulld n --imsys y --survey Y1 --verspec iron --imsys_zbin y --version $VERSION --use_map_veto _HPmapcut --clusd y --clusran y --minr 0 --maxr $NUM_RAND --compmd altmtl --absmagmd phot --imsys_colname WEIGHT_IMLIN --splitGC y --nz y --bgs_mag ${magnitude[$m]} --bgs_mag_zmin 0.05 --bgs_mag_zmax ${zmax[$m]}
  
  # Add the magnitudes and colours to the clustering catalogues and randoms
  for r in "${region[@]}"
  do
    python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT-21.5_${r}clustering.dat.fits
    for i in `seq 0 $NUM_RAND_LOOP`
    do 
      python $LSS_DIR/hodpy/tools/add_magnitudes_colours.py $OUTPUT_DIR/BGS_BRIGHT-21.5_${r}${i}_clustering.ran.fits
    done
  done

  # Move to a new directory to make sure they aren't overwritten
  mkdir $OUTPUT_DIR/MAG${magnitude[$m]}
  mv $OUTPUT_DIR/BGS_BRIGHT-21.5_* $OUTPUT_DIR/MAG${magnitude[$m]}/
  
done
