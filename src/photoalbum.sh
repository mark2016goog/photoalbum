#!/bin/bash

# photoalbum (c) 2011 - 2014 by Paul C. Buetow
# http://photoalbum.buetow.org

readonly VERSION='PHOTOALBUMVERSION'
readonly DEFAULTRC=/etc/default/photoalbum
readonly ARG1="${1}"    ; shift
declare  RC_FILE="${1}" ; shift

function usage() {
  cat - <<USAGE >&2
  Usage: 
  $0 clean|init|version|generate|all [rcfile]
USAGE
}

function makemake() {
  [ ! -f ./photoalbumrc ] && cp /etc/default/photoalbum ./photoalbumrc
  cat <<MAKEFILE > ./Makefile
all:
	photoalbum generate photoalbumrc
clean:
	photoalbum clean photoalbumrc
MAKEFILE
  echo You may now customize ./photoalbumrc and run make
}

function tarball() {
  # Cleanup tarball from prev run if any
  find "${DIST_DIR}" -maxdepth 1 -type f -name \*.tar -delete
  readonly base=$(basename "${INCOMING_DIR}")

  echo "Creating tarball ${DIST_DIR}/${tarball_name} from ${INCOMING_DIR}"
  cd $(dirname "${INCOMING_DIR}")
  tar $TAR_OPTS  -f "${DIST_DIR}/${tarball_name}" "${base}"
  cd - &>/dev/null
}

function template() {
  readonly template=${1}  ; shift
  readonly html=${1}      ; shift
  readonly dist_html="${DIST_DIR}/${html_dir}"

  # Creating ${dist_html}/${html}.html from ${template}.tmpl
  [ ! -d "${dist_html}" ] && mkdir -p "${dist_html}"
  source "${TEMPLATE_DIR}/${template}.tmpl" >> "${dist_html}/${html}"
}

function scalephotos() {
  cd "${INCOMING_DIR}" && find ./ -type f | sort |
  while read photo; do
    declare photo=$(sed 's#^\./##' <<< "${photo}")
    declare destphoto="${DIST_DIR}/photos/${photo}"
    declare destphoto_nospace=${destphoto// /_}

    declare dirname=$(dirname "${destphoto}")
    [ ! -d "${dirname}" ] && mkdir -p "${dirname}"

    if [ ! -f "${destphoto_nospace}" ]; then
      echo "Scaling ${photo} to ${destphoto_nospace}"
      convert -auto-orient \
        -geometry ${GEOMETRY} "${photo}" "${destphoto_nospace}"
    fi
  done
}

function albumhtml() {
  declare photos_dir="${1}" ; shift
  declare html_dir="${1}"   ; shift
  declare thumbs_dir="${1}" ; shift
  declare backhref="${1}"   ; shift

  declare -i num=1
  declare -i i=0

  declare name=page-${num}

  template header ${name}.html
  template header-first-add ${name}.html

  cd "${DIST_DIR}/${photos_dir}" && find ./ -type f | sort | sed 's;^\./;;' |
  while read photo; do 
    : $(( i++ ))

    if [ ${i} -gt ${MAXPREVIEWS} ]; then
      i=1
      : $(( num++ ))

      declare next=page-${num}
      template next ${name}.html
      template footer ${name}.html

      declare prev=${name}
      declare name=${next}
      template header ${name}.html
      template prev ${name}.html
    fi

    # Preview page
    template preview ${name}.html

    # View page
    template header ${num}-${i}.html
    template view ${num}-${i}.html
    template footer ${num}-${i}.html

    if [ ! -f "${DIST_DIR}/${thumbs_dir}/${photo}" ]; then 
      dirname=$(dirname "${DIST_DIR}/${thumbs_dir}/${photo}")
      [ ! -d "${dirname}" ] && mkdir -p "${dirname}"

      echo "Creating thumb ${DIST_DIR}/${thumbs_dir}/${photo}";
      convert -geometry x${THUMBGEOMETRY} "${photo}" \
        "${DIST_DIR}/${thumbs_dir}/${photo}"
    fi
  done

  template footer \
    $(cd "${DIST_DIR}/${html_dir}";ls -t page-*.html | head -n 1)

  cd "${DIST_DIR}/${html_dir}" && ls *.html | grep -v page- | cut -d'-' -f1 | uniq |
  while read prefix; do 
    declare page=$(ls -t ${prefix}-*.html |
    head -n 1 | sed 's#\(.*\)-.*.html#\1#')

    declare lastview=$(ls -t ${prefix}-*.html |
    head -n 1 | sed 's/.*-\(.*\).html/\1/')

    declare prevredirect=${page}-0
    declare nextredirect=${page}-$((lastview+1))

    declare redirect_page=$(( page-1 ))-${MAXPREVIEWS}
    template redirect ${prevredirect}.html

    if [ ${lastview} -eq ${MAXPREVIEWS} ]; then
      declare redirect_page=$(( page+1 ))-1

    else
      declare redirect_page=${page}-${lastview}
      template redirect 0-${MAXPREVIEWS}.html
      redirect_page=1-1
    fi
    template redirect ${nextredirect}.html
  done

  # Create per album index/redirect page
  declare redirect_page=page-1
  template redirect index.html
}

function albumindexhtml() {
  declare -a dirs=( "${1}" )
  declare is_subalbum=no
  declare html_dir=html
  declare backhref=..

  template header index.html
  template header-first-add index.html

  for dir in ${dirs[*]}; do
    declare basename=$(basename "$dir")
    declare album=$basename
    declare thumbs_dir="${DIST_DIR}/thumbs/${basename}"
    declare pictures=$(ls "${thumbs_dir}" | wc -l)
    declare random_num=$(( 1 + $RANDOM % $pictures ))
    declare pages=$(( $pictures / $MAXPREVIEWS + 1 ))

    declare random_thumb="./thumbs/${basename}"/$(find \
      "${thumbs_dir}" -type f -printf "%f\n" |
      head -n ${random_num} | tail -n 1)

    [ ${pages} -gt 1 ] && declare s=s || declare s=''
    declare description="${pictures} pictures / ${pages} page${s}"
    template index-preview index.html
  done

  template footer index.html
}

function generate() {
  if [ ! -d "${INCOMING_DIR}" ]; then
    echo "ERROR: You have to create ${INCOMING_DIR} first" >&2
    exit 1
  fi

  if [ "${TARBALL_INCLUDE}" = yes ]; then
    readonly base=$(basename "${INCOMING_DIR}")
    readonly now=$(date +'%Y-%m-%d-%H%M%S')
    readonly tarball_name="${base}-${now}${TARBALL_SUFFIX}"
  fi

  scalephotos

  find "${DIST_DIR}" -type f -name \*.html -delete
  declare -a dirs=( $(find "${DIST_DIR}/photos" \
    -mindepth 1 -maxdepth 1 -type d | sort) )

  # Figure out wether we want sub-albums or not
  if [[ "${SUB_ALBUMS}" != yes || ${#dirs[*]} -eq 0 ]]; then
    declare is_subalbum=no
    albumhtml photos html thumbs ..

  else
    declare is_subalbum=yes
    for dir in ${dirs[*]}; do
      declare basename=$(basename "${dir}")
      albumhtml \
        "photos/${basename}" "html/${basename}" "thumbs/${basename}" ../..
    done

    # Create an album selection screen
    albumindexhtml "${dirs[*]}"
  fi

  # Create top level index/redirect page
  declare html_dir=./
  declare redirect_page=./html/index
  template redirect index.html

  if [ "${TARBALL_INCLUDE}" = yes ]; then
    tarball
  fi
}

if [ -z "${RC_FILE}" ]; then
  if [ -f ~/.photoalbumrc ]; then
    RC_FILE=~/.photoalbumrc
  else
    RC_FILE="${DEFAULTRC}"
  fi
fi

if [ ! -f "${RC_FILE}" ]; then
  echo "Error: Can not find config file ${RC_FILE}" >&2
  exit 1
fi

source "${RC_FILE}"

case "${ARG1}" in
  clean)    [ -d "${DIST_DIR}" ] && rm -Rf "${DIST_DIR}";;
  generate) generate;;
  version)  echo "This is Photoalbum Version ${VERSION}";;
  makemake) makemake;;
  *)        usage;;
esac

exit 0

