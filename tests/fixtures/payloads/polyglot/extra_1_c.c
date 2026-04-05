// SPDX-License-Identifier: GPL-2.0
/*
 *  linux/fs/ext4/inode.c
 *
 * Copyright (C) 1992, 1993, 1994, 1995
 * Remy Card (card@masi.ibp.fr)
 * Laboratoire MASI - Institut Blaise Pascal
 * Universite Pierre et Marie Curie (Paris VI)
 *
 *  from
 *
 *  linux/fs/minix/inode.c
 *
 *  Copyright (C) 1991, 1992  Linus Torvalds
 *
 *  64-bit file support on 64-bit platforms by Jakub Jelinek
 *	(jj@sunsite.ms.mff.cuni.cz)
 *
 *  Assorted race fixes, rewrite of ext4_get_block() by Al Viro, 2000
 */

#include <linux/fs.h>
#include <linux/mount.h>
#include <linux/time.h>
#include <linux/highuid.h>
#include <linux/pagemap.h>
#include <linux/dax.h>
#include <linux/quotaops.h>
#include <linux/string.h>
#include <linux/buffer_head.h>
#include <linux/writeback.h>
#include <linux/pagevec.h>
#include <linux/mpage.h>
#include <linux/rmap.h>
#include <linux/namei.h>
#include <linux/uio.h>
#include <linux/bio.h>
#include <linux/workqueue.h>
#include <linux/kernel.h>
#include <linux/printk.h>
#include <linux/slab.h>
#include <linux/bitops.h>
#include <linux/iomap.h>
#include <linux/iversion.h>

#include "ext4_jbd2.h"
#include "xattr.h"
#include "acl.h"
#include "truncate.h"

#include <kunit/static_stub.h>

#include <trace/events/ext4.h>

static void ext4_journalled_zero_new_buffers(handle_t *handle,
					    struct inode *inode,
					    struct folio *folio,
					    unsigned from, unsigned to);

static __u32 ext4_inode_csum(struct inode *inode, struct ext4_inode *raw,
			      struct ext4_inode_info *ei)
{
	__u32 csum;
	__u16 dummy_csum = 0;
	int offset = offsetof(struct ext4_inode, i_checksum_lo);
	unsigned int csum_size = sizeof(dummy_csum);

	csum = ext4_chksum(ei->i_csum_seed, (__u8 *)raw, offset);
	csum = ext4_chksum(csum, (__u8 *)&dummy_csum, csum_size);
	offset += csum_size;
	csum = ext4_chksum(csum, (__u8 *)raw + offset,
			   EXT4_GOOD_OLD_INODE_SIZE - offset);

	if (EXT4_INODE_SIZE(inode->i_sb) > EXT4_GOOD_OLD_INODE_SIZE) {
		offset = offsetof(struct ext4_inode, i_checksum_hi);
		csum = ext4_chksum(csum, (__u8 *)raw + EXT4_GOOD_OLD_INODE_SIZE,
				   offset - EXT4_GOOD_OLD_INODE_SIZE);
		if (EXT4_FITS_IN_INODE(raw, ei, i_checksum_hi)) {
			csum = ext4_chksum(csum, (__u8 *)&dummy_csum,
					   csum_size);
			offset += csum_size;
		}
		csum = ext4_chksum(csum, (__u8 *)raw + offset,
				   EXT4_INODE_SIZE(inode->i_sb) - offset);
	}

	return csum;
}

static int ext4_inode_csum_verify(struct inode *inode, struct ext4_inode *raw,
				  struct ext4_inode_info *ei)
{
	__u32 provided, calculated;

	if (EXT4_SB(inode->i_sb)->s_es->s_creator_os !=
	    cpu_to_le32(EXT4_OS_LINUX) ||
	    !ext4_has_feature_metadata_csum(inode->i_sb))
		return 1;

	provided = le16_to_cpu(raw->i_checksum_lo);
	calculated = ext4_inode_csum(inode, raw, ei);
	if (EXT4_INODE_SIZE(inode->i_sb) > EXT4_GOOD_OLD_INODE_SIZE &&
	    EXT4_FITS_IN_INODE(raw, ei, i_checksum_hi))
		provided |= ((__u32)le16_to_cpu(raw->i_checksum_hi)) << 16;
	else
		calculated &= 0xFFFF;

	return provided == calculated;
}

void ext4_inode_csum_set(struct inode *inode, struct ext4_inode *raw,
			 struct ext4_inode_info *ei)
{
	__u32 csum;

	if (EXT4_SB(inode->i_sb)->s_es->s_creator_os !=
	    cpu_to_le32(EXT4_OS_LINUX) ||
	    !ext4_has_feature_metadata_csum(inode->i_sb))
		return;

	csum = ext4_inode_csum(inode, raw, ei);
	raw->i_checksum_lo = cpu_to_le16(csum & 0xFFFF);
	if (EXT4_INODE_SIZE(inode->i_sb) > EXT4_GOOD_OLD_INODE_SIZE &&
	    EXT4_FITS_IN_INODE(raw, ei, i_checksum_hi))
		raw->i_checksum_hi = cpu_to_le16(csum >> 16);
}

static inline int ext4_begin_ordered_truncate(struct inode *inode,
					      loff_t new_size)
{
	struct jbd2_inode *jinode = READ_ONCE(EXT4_I(inode)->jinode);

	trace_ext4_begin_ordered_truncate(inode, new_size);
	/*
	 * If jinode is zero, then we never opened the file for
	 * writing, so there's no need to call
	 * jbd2_journal_begin_ordered_truncate() since there's no
	 * outstanding writes we need to flush.
	 */
	if (!jinode)
		return 0;
	return jbd2_journal_begin_ordered_truncate(EXT4_JOURNAL(inode),
						   jinode,
						   new_size);
}

/*
 * Test whether an inode is a fast symlink.
 * A fast symlink has its symlink data stored in ext4_inode_info->i_data.
 */
int ext4_inode_is_fast_symlink(struct inode *inode)
{
	if (!ext4_has_feature_ea_inode(inode->i_sb)) {
		int ea_blocks = EXT4_I(inode)->i_file_acl ?
				EXT4_CLUSTER_SIZE(inode->i_sb) >> 9 : 0;

		if (ext4_has_inline_data(inode))
			return 0;

		return (S_ISLNK(inode->i_mode) && inode->i_blocks - ea_blocks == 0);
	}
	return S_ISLNK(inode->i_mode) && inode->i_size &&
	       (inode->i_size < EXT4_N_BLOCKS * 4);
}

/*
 * Called at the last iput() if i_nlink is zero.
 */
void ext4_evict_inode(struct inode *inode)
{
	handle_t *handle;
	int err;
	/*
	 * Credits for final inode cleanup and freeing:
	 * sb + inode (ext4_orphan_del()), block bitmap, group descriptor
	 * (xattr block freeing), bitmap, group descriptor (inode freeing)
	 */
	int extra_credits = 6;
	struct ext4_xattr_inode_array *ea_inode_array = NULL;
	bool freeze_protected = false;

	trace_ext4_evict_inode(inode);

	dax_break_layout_final(inode);

	if (EXT4_I(inode)->i_flags & EXT4_EA_INODE_FL)
		ext4_evict_ea_inode(inode);
	if (inode->i_nlink) {
		/*
		 * If there's dirty page will lead to data loss, user
		 * could see stale data.
		 */
		if (unlikely(!ext4_emergency_state(inode->i_sb) &&
		    mapping_tagged(&inode->i_data, PAGECACHE_TAG_DIRTY)))
			ext4_warning_inode(inode, "data will be lost");

		truncate_inode_pages_final(&inode->i_data);

		goto no_delete;
	}

	if (is_bad_inode(inode))
		goto no_delete;
	dquot_initialize(inode);

	if (ext4_should_order_data(inode))
		ext4_begin_ordered_truncate(inode, 0);
	truncate_inode_pages_final(&inode->i_data);

	/*
	 * For inodes with journalled data, transaction commit could have
	 * dirtied the inode. And for inodes with dioread_nolock, unwritten
	 * extents converting worker could merge extents and also have dirtied
	 * the inode. Flush worker is ignoring it because of I_FREEING flag but
	 * we still need to remove the inode from the writeback lists.
	 */
	inode_io_list_del(inode);

	/*
	 * Protect us against freezing - iput() caller didn't have to have any
	 * protection against it. When we are in a running transaction though,
	 * we are already protected against freezing and we cannot grab further
	 * protection due to lock ordering constraints.
	 */
	if (!ext4_journal_current_handle()) {
		sb_start_intwrite(inode->i_sb);
		freeze_protected = true;
	}

	if (!IS_NOQUOTA(inode))
		extra_credits += EXT4_MAXQUOTAS_DEL_BLOCKS(inode->i_sb);

	/*
	 * Block bitmap, group descriptor, and inode are accounted in both
	 * ext4_blocks_for_truncate() and extra_credits. So subtract 3.
	 */
	handle = ext4_journal_start(inode, EXT4_HT_TRUNCATE,
			 ext4_blocks_for_truncate(inode) + extra_credits - 3);
	if (IS_ERR(handle)) {
		ext4_std_error(inode->i_sb, PTR_ERR(handle));
		/*
		 * If we're going to skip the normal cleanup, we still need to
		 * make sure that the in-core orphan linked list is properly
		 * cleaned up.
		 */
		ext4_orphan_del(NULL, inode);
		if (freeze_protected)
			sb_end_intwrite(inode->i_sb);
		goto no_delete;
	}

	if (IS_SYNC(inode))
		ext4_handle_sync(handle);

	/*
	 * Set inode->i_size to 0 before calling ext4_truncate(). We need
	 * special handling of symlinks here because i_size is used to
	 * determine whether ext4_inode_info->i_data contains symlink data or
	 * block mappings. Setting i_size to 0 will remove its fast symlink
	 * status. Erase i_data so that it becomes a valid empty block map.
	 */
	if (ext4_inode_is_fast_symlink(inode))
		memset(EXT4_I(inode)->i_data, 0, sizeof(EXT4_I(inode)->i_data));
	inode->i_size = 0;
	err = ext4_mark_inode_dirty(handle, inode);
	if (err) {
		ext4_warning(inode->i_sb,
			     "couldn't mark inode dirty (err %d)", err);
		goto stop_handle;
	}
	if (inode->i_blocks) {
		err = ext4_truncate(inode);
		if (err) {
			ext4_error_err(inode->i_sb, -err,
				       "couldn't truncate inode %lu (err %d)",
				       inode->i_ino, err);
			goto stop_handle;
		}
	}

	/* Remove xattr references. */
	err = ext4_xattr_delete_inode(handle, inode, &ea_inode_array,
				      extra_credits);
	if (err) {
		ext4_warning(inode->i_sb, "xattr delete (err %d)", err);
stop_handle:
		ext4_journal_stop(handle);
		ext4_orphan_del(NULL, inode);
		if (freeze_protected)
			sb_end_intwrite(inode->i_sb);
		ext4_xattr_inode_array_free(ea_inode_array);
		goto no_delete;
	}

	/*
	 * Kill off the orphan record which ext4_truncate created.
	 * AKPM: I think this can be inside the above `if'.
	 * Note that ext4_orphan_del() has to be able to cope with the
	 * deletion of a non-existent orphan - this is because we don't
	 * know if ext4_truncate() actually created an orphan record.
	 * (Well, we could do this if we need to, but heck - it works)
	 */
	ext4_orphan_del(handle, inode);
	EXT4_I(inode)->i_dtime	= (__u32)ktime_get_real_seconds();

	/*
	 * One subtle ordering requirement: if anything has gone wrong
	 * (transaction abort, IO errors, whatever), then we can still
	 * do these next steps (the fs will already have been marked as
	 * having errors), but we can't free the inode if the mark_dirty
	 * fails.
	 */
	if (ext4_mark_inode_dirty(handle, inode))
		/* If that failed, just do the required in-core inode clear. */
		ext4_clear_inode(inode);
	else
		ext4_free_inode(handle, inode);
	ext4_journal_stop(handle);
	if (freeze_protected)
		sb_end_intwrite(inode->i_sb);
	ext4_xattr_inode_array_free(ea_inode_array);
	return;
no_delete:
	/*
	 * Check out some where else accidentally dirty the evicting inode,
	 * which may probably cause inode use-after-free issues later.
	 */
	WARN_ON_ONCE(!list_empty_careful(&inode->i_io_list));

	if (!list_empty(&EXT4_I(inode)->i_fc_list))
		ext4_fc_mark_ineligible(inode->i_sb, EXT4_FC_REASON_NOMEM, NULL);
	ext4_clear_inode(inode);	/* We must guarantee clearing of inode... */
}

#ifdef CONFIG_QUOTA
qsize_t *ext4_get_reserved_space(struct inode *inode)
{
	return &EXT4_I(inode)->i_reserved_quota;
}
#endif

/*
 * Called with i_data_sem down, which is important since we can call
 * ext4_discard_preallocations() from here.
 */
void ext4_da_update_reserve_space(struct inode *inode,
					int used, int quota_claim)
{
	struct ext4_sb_info *sbi = EXT4_SB(inode->i_sb);
	struct ext4_inode_info *ei = EXT4_I(inode);

	spin_lock(&ei->i_block_reservation_lock);
	trace_ext4_da_update_reserve_space(inode, used, quota_claim);
	if (unlikely(used > ei->i_reserved_data_blocks)) {
		ext4_warning(inode->i_sb, "%s: ino %lu, used %d "
			 "with only %d reserved data blocks",
			 __func__, inode->i_ino, used,
			 ei->i_reserved_data_blocks);
		WARN_ON(1);
		used = ei->i_reserved_data_blocks;
	}

	/* Update per-inode reservations */
	ei->i_reserved_data_blocks -= used;
	percpu_counter_sub(&sbi->s_dirtyclusters_counter, used);

	spin_unlock(&ei->i_block_reservation_lock);

	/* Update quota subsystem for data blocks */
	if (quota_claim)
		dquot_claim_block(inode, EXT4_C2B(sbi, used));
	else {
		/*
		 * We did fallocate with an offset that is already delayed
		 * allocated. So on delayed allocated writeback we should
		 * not re-claim the quota for fallocated blocks.
		 */
		dquot_release_reservation_block(inode, EXT4_C2B(sbi, used));
	}

	/*
	 * If we have done all the pending block allocations and if
	 * there aren't any writers on the inode, we can discard the
	 * inode's preallocations.
	 */
	if ((ei->i_reserved_data_blocks == 0) &&
	    !inode_is_open_for_write(inode))
		ext4_discard_preallocations(inode);
}

static int __check_block_validity(struct inode *inode, const char *func,
				unsigned int line,
				struct ext4_map_blocks *map)
{
	journal_t *journal = EXT4_SB(inode->i_sb)->s_journal;

	if (journal && inode == journal->j_inode)
		return 0;

	if (!ext4_inode_block_valid(inode, map->m_pblk, map->m_len)) {
		ext4_error_inode(inode, func, line, map->m_pblk,
				 "lblock %lu mapped to illegal pblock %llu "
				 "(length %d)", (unsigned long) map->m_lblk,
				 map->m_pblk, map->m_len);
		return -EFSCORRUPTED;
	}
	return 0;
}

int ext4_issue_zeroout(struct inode *inode, ext4_lblk_t lblk, ext4_fsblk_t pblk,
		       ext4_lblk_t len)
{
	int ret;

	KUNIT_STATIC_STUB_REDIRECT(ext4_issue_zeroout, inode, lblk, pblk, len);

	if (IS_ENCRYPTED(inode) && S_ISREG(inode->i_mode))
		return fscrypt_zeroout_range(inode, lblk, pblk, len);

	ret = sb_issue_zeroout(inode->i_sb, pblk, len, GFP_NOFS);
	if (ret > 0)
		ret = 0;

	return ret;
}

/*
 * For generic regular files, when updating the extent tree, Ext4 should
 * hold the i_rwsem and invalidate_lock exclusively. This ensures
 * exclusion against concurrent page faults, as well as reads and writes.
 */
#ifdef CONFIG_EXT4_DEBUG
void ext4_check_map_extents_env(struct inode *inode)
{
	if (EXT4_SB(inode->i_sb)->s_mount_state & EXT4_FC_REPLAY)
		return;

	if (!S_ISREG(inode->i_mode) ||
	    IS_NOQUOTA(inode) || IS_VERITY(inode) ||
	    is_special_ino(inode->i_sb, inode->i_ino) ||
	    (inode_state_read_once(inode) & (I_FREEING | I_WILL_FREE | I_NEW)) ||
	    ext4_test_inode_flag(inode, EXT4_INODE_EA_INODE) ||
	    ext4_verity_in_progress(inode))
		return;

	WARN_ON_ONCE(!inode_is_locked(inode) &&
		     !rwsem_is_locked(&inode->i_mapping->invalidate_lock));
}
#else
void ext4_check_map_extents_env(struct inode *inode) {}
#endif

#define check_block_validity(inode, map)	\
	__check_block_validity((inode), __func__, __LINE__, (map))

#ifdef ES_AGGRESSIVE_TEST
static void ext4_map_blocks_es_recheck(handle_t *handle,
				       struct inode *inode,
				       struct ext4_map_blocks *es_map,
				       struct ext4_map_blocks *map,
				       int flags)
{
	int retval;

	map->m_flags = 0;
	/*
	 * There is a race window that the result is not the same.
	 * e.g. xfstests #223 when dioread_nolock enables.  The reason
	 * is that we lookup a block mapping in extent status tree with
	 * out taking i_data_sem.  So at the time the unwritten extent
	 * could be converted.
	 */
	down_read(&EXT4_I(inode)->i_data_sem);
	if (ext4_test_inode_flag(inode, EXT4_INODE_EXTENTS)) {
		retval = ext4_ext_map_blocks(handle, inode, map, 0);
	} else {
		retval = ext4_ind_map_blocks(handle, inode, map, 0);
	}
	up_read((&EXT4_I(inode)->i_data_sem));

	/*
	 * We don't check m_len because extent will be collpased in status
	 * tree.  So the m_len might not equal.
	 */
	if (es_map->m_lblk != map->m_lblk ||
	    es_map->m_flags != map->m_flags ||
	    es_map->m_pblk != map->m_pblk) {
		printk("ES cache assertion failed for inode: %lu "
		       "es_cached ex [%d/%d/%llu/%x] != "
		       "found ex [%d/%d/%llu/%x] retval %d flags %x\n",
		       inode->i_ino, es_map->m_lblk, es_map->m_len,
		       es_map->m_pblk, es_map->m_flags, map->m_lblk,
		       map->m_len, map->m_pblk, map->m_flags,
		       retval, flags);
	}
}
#endif /* ES_AGGRESSIVE_TEST */

static int ext4_map_query_blocks_next_in_leaf(handle_t *handle,
			struct inode *inode, struct ext4_map_blocks *map,
			unsigned int orig_mlen)
{
	struct ext4_map_blocks map2;
	unsigned int status, status2;
	int retval;

	status = map->m_flags & EXT4_MAP_UNWRITTEN ?
		EXTENT_STATUS_UNWRITTEN : EXTENT_STATUS_WRITTEN;

	WARN_ON_ONCE(!(map->m_flags & EXT4_MAP_QUERY_LAST_IN_LEAF));
	WARN_ON_ONCE(orig_mlen <= map->m_len);

	/* Prepare map2 for lookup in next leaf block */
	map2.m_lblk = map->m_lblk + map->m_len;
	map2.m_len = orig_mlen - map->m_len;
	map2.m_flags = 0;
	retval = ext4_ext_map_blocks(handle, inode, &map2, 0);

	if (retval <= 0) {
		ext4_es_cache_extent(inode, map->m_lblk, map->m_len,
				     map->m_pblk, status);
		return map->m_len;
	}

	if (unlikely(retval != map2.m_len)) {
		ext4_warning(inode->i_sb,
			     "ES len assertion failed for inode "
			     "%lu: retval %d != map->m_len %d",
			     inode->i_ino, retval, map2.m_len);
		WARN_ON(1);
	}

	status2 = map2.m_flags & EXT4_MAP_UNWRITTEN ?
		EXTENT_STATUS_UNWRITTEN : EXTENT_STATUS_WRITTEN;

	/*
	 * If map2 is contiguous with map, then let's insert it as a single
	 * extent in es cache and return the combined length of both the maps.
	 */
	if (map->m_pblk + map->m_len == map2.m_pblk &&
			status == status2) {
		ext4_es_cache_extent(inode, map->m_lblk,
				     map->m_len + map2.m_len, map->m_pblk,
				     status);
		map->m_len += map2.m_len;
	} else {
		ext4_es_cache_extent(inode, map->m_lblk, map->m_len,
				     map->m_pblk, status);
	}

	return map->m_len;
}

int ext4_map_query_blocks(handle_t *handle, struct inode *inode,
			  struct ext4_map_blocks *map, int flags)
{
	unsigned int status;
	int retval;
	unsigned int orig_mlen = map->m_len;

	flags &= EXT4_EX_QUERY_FILTER;
	if (ext4_test_inode_flag(inode, EXT4_INODE_EXTENTS))
		retval = ext4_ext_map_blocks(handle, inode, map, flags);
	else
		retval = ext4_ind_map_blocks(handle, inode, map, flags);
	if (retval < 0)
		return retval;

	/* A hole? */
	if (retval == 0)
		goto out;

	if (unlikely(retval != map->m_len)) {
		ext4_warning(inode->i_sb,
			     "ES len assertion failed for inode "
			     "%lu: retval %d != map->m_len %d",
			     inode->i_ino, retval, map->m_len);
		WARN_ON(1);
	}

	/*
	 * No need to query next in leaf:
	 * - if returned extent is not last in leaf or
	 * - if the last in leaf is the full requested range
	 */
	if (!(map->m_flags & EXT4_MAP_QUERY_LAST_IN_LEAF) ||
			map->m_len == orig_mlen) {
		status = map->m_flags & EXT4_MAP_UNWRITTEN ?
				EXTENT_STATUS_UNWRITTEN : EXTENT_STATUS_WRITTEN;
		ext4_es_cache_extent(inode, map->m_lblk, map->m_len,
				     map->m_pblk, status);
	} else {
		retval = ext4_map_query_blocks_next_in_leaf(handle, inode, map,
							    orig_mlen);
	}
out:
	map->m_seq = READ_ONCE(EXT4_I(inode)->i_es_seq);
	return retval;
}

int ext4_map_create_blocks(handle_t *handle, struct inode *inode,
			   struct ext4_map_blocks *map, int flags)
{
	unsigned int status;
	int err, retval = 0;

	/*
	 * We pass in the magic EXT4_GET_BLOCKS_DELALLOC_RESERVE
	 * indicates that the blocks and quotas has already been
	 * checked when the data was copied into the page cache.
	 */
	if (map->m_flags & EXT4_MAP_DELAYED)
		flags |= EXT4_GET_BLOCKS_DELALLOC_RESERVE;

	/*
	 * Here we clear m_flags because after allocating an new extent,
	 * it will be set again.
	 */
	map->m_flags &= ~EXT4_MAP_FLAGS;

	/*
	 * We need to check for EXT4 here because migrate could have
	 * changed the inode type in between.
	 */
	if (ext4_test_inode_flag(inode, EXT4_INODE_EXTENTS)) {
		retval = ext4_ext_map_blocks(handle, inode, map, flags);
	} else {
		retval = ext4_ind_map_blocks(handle, inode, map, flags);

		/*
		 * We allocated new blocks which will result in i_data's
		 * format changing. Force the migrate to fail by clearing
		 * migrate flags.
		 */
		if (retval > 0 && map->m_flags & EXT4_MAP_NEW)
			ext4_clear_inode_state(inode, EXT4_STATE_EXT_MIGRATE);
	}
	if (retval <= 0)
		return retval;

	if (unlikely(retval != map->m_len)) {
		ext4_warning(inode->i_sb,
			     "ES len assertion failed for inode %lu: "
			     "retval %d != map->m_len %d",
			     inode->i_ino, retval, map->m_len);
		WARN_ON(1);
	}

	/*
	 * We have to zeroout blocks before inserting them into extent
	 * status tree. Otherwise someone could look them up there and
	 * use them before they are really zeroed. We also have to
	 * unmap metadata before zeroing as otherwise writeback can
	 * overwrite zeros with stale data from block device.
	 */
	if (flags & EXT4_GET_BLOCKS_ZERO &&
	    map->m_flags & EXT4_MAP_MAPPED && map->m_flags & EXT4_MAP_NEW) {
		err = ext4_issue_zeroout(inode, map->m_lblk, map->m_pblk,
					 map->m_len);
		if (err)
			return err;
	}

	status = map->m_flags & EXT4_MAP_UNWRITTEN ?
			EXTENT_STATUS_UNWRITTEN : EXTENT_STATUS_WRITTEN;
	ext4_es_insert_extent(inode, map->m_lblk, map->m_len, map->m_pblk,
			      status, flags & EXT4_GET_BLOCKS_DELALLOC_RESERVE);
	map->m_seq = READ_ONCE(EXT4_I(inode)->i_es_seq);

	return retval;
}

/*
 * The ext4_map_blocks() function tries to look up the requested blocks,
 * and returns if the blocks are already mapped.
 *
 * Otherwise it takes the write lock of the i_data_sem and allocate blocks
 * and store the allocated blocks in the result buffer head and mark it
 * mapped.
 *
 * If file type is extents based, it will call ext4_ext_map_blocks(),
 * Otherwise, call with ext4_ind_map_blocks() to handle indirect mapping
 * based files
 *
 * On success, it returns the number of blocks being mapped or allocated.
 * If flags doesn't contain EXT4_GET_BLOCKS_CREATE the blocks are
 * pre-allocated and unwritten, the resulting @map is marked as unwritten.
 * If the flags contain EXT4_GET_BLOCKS_CREATE, it will mark @map as mapped.
 *
 * It returns 0 if plain look up failed (blocks have not been allocated), in
 * that case, @map is returned as unmapped but we still do fill map->m_len to
 * indicate the length of a hole starting at map->m_lblk.
 *
 * It returns the error in case of allocation failure.
 */
int ext4_map_blocks(handle_t *handle, struct inode *inode,
		    struct ext4_map_blocks *map, int flags)
{
	struct extent_status es;
	int retval;
	int ret = 0;
	unsigned int orig_mlen = map->m_len;
#ifdef ES_AGGRESSIVE_TEST
	struct ext4_map_blocks orig_map;

	memcpy(&orig_map, map, sizeof(*map));
#endif

	map->m_flags = 0;
	ext_debug(inode, "flag 0x%x, max_blocks %u, logical block %lu\n",
		  flags, map->m_len, (unsigned long) map->m_lblk);

	/*
	 * ext4_map_blocks returns an int, and m_len is an unsigned int
	 */
	if (unlikely(map->m_len > INT_MAX))
		map->m_len = INT_MAX;

	/* We can handle the block number less than EXT_MAX_BLOCKS */
	if (unlikely(map->m_lblk >= EXT_MAX_BLOCKS))
		return -EFSCORRUPTED;

	/*
	 * Callers from the context of data submission are the only exceptions
	 * for regular files that do not hold the i_rwsem or invalidate_lock.
	 * However, caching unrelated ranges is not permitted.
	 */
	if (flags & EXT4_GET_BLOCKS_IO_SUBMIT)
		WARN_ON_ONCE(!(flags & EXT4_EX_NOCACHE));
	else
		ext4_check_map_extents_env(inode);

	/* Lookup extent status tree firstly */
	if (ext4_es_lookup_extent(inode, map->m_lblk, NULL, &es, &map->m_seq)) {
		if (ext4_es_is_written(&es) || ext4_es_is_unwritten(&es)) {
			map->m_pblk = ext4_es_pblock(&es) +
					map->m_lblk - es.es_lblk;
			map->m_flags |= ext4_es_is_written(&es) ?
					EXT4_MAP_MAPPED : EXT4_MAP_UNWRITTEN;
			retval = es.es_len - (map->m_lblk - es.es_lblk);
			if (retval > map->m_len)
				retval = map->m_len;
			map->m_len = retval;
		} else if (ext4_es_is_delayed(&es) || ext4_es_is_hole(&es)) {
			map->m_pblk = 0;
			map->m_flags |= ext4_es_is_delayed(&es) ?
					EXT4_MAP_DELAYED : 0;
			retval = es.es_len - (map->m_lblk - es.es_lblk);
			if (retval > map->m_len)
				retval = map->m_len;
			map->m_len = retval;
			retval = 0;
		} else {
			BUG();
		}

		if (flags & EXT4_GET_BLOCKS_CACHED_NOWAIT)
			return retval;
#ifdef ES_AGGRESSIVE_TEST
		ext4_map_blocks_es_recheck(handle, inode, map,
					   &orig_map, flags);
#endif
		if (!(flags & EXT4_GET_BLOCKS_QUERY_LAST_IN_LEAF) ||
				orig_mlen == map->m_len)
			goto found;

		map->m_len = orig_mlen;
	}
	/*
	 * In the query cache no-wait mode, nothing we can do more if we
	 * cannot find extent in the cache.
	 */
	if (flags & EXT4_GET_BLOCKS_CACHED_NOWAIT)
		return 0;

	/*
	 * Try to see if we can get the block without requesting a new
	 * file system block.
	 */
	down_read(&EXT4_I(inode)->i_data_sem);
	retval = ext4_map_query_blocks(handle, inode, map, flags);
	up_read((&EXT4_I(inode)->i_data_sem));

found:
	if (retval > 0 && map->m_flags & EXT4_MAP_MAPPED) {
		ret = check_block_validity(inode, map);
		if (ret != 0)
			return ret;
	}

	/* If it is only a block(s) look up */
	if ((flags & EXT4_GET_BLOCKS_CREATE) == 0)
		return retval;

	/*
	 * Returns if the blocks have already allocated
	 *
	 * Note that if blocks have been preallocated
	 * ext4_ext_map_blocks() returns with buffer head unmapped
	 */
	if (retval > 0 && map->m_flags & EXT4_MAP_MAPPED)
		/*
		 * If we need to convert extent to unwritten
		 * we continue and do the actual work in
		 * ext4_ext_map_blocks()
		 */
		if (!(flags & EXT4_GET_BLOCKS_CONVERT_UNWRITTEN))
			return retval;


	ext4_fc_track_inode(handle, inode);
	/*
	 * New blocks allocate and/or writing to unwritten extent
	 * will possibly result in updating i_data, so we take
	 * the write lock of i_data_sem, and call get_block()
	 * with create == 1 flag.
	 */
	down_write(&EXT4_I(inode)->i_data_sem);
	retval = ext4_map_create_blocks(handle, inode, map, flags);
	up_write((&EXT4_I(inode)->i_data_sem));

	if (retval < 0)
		ext_debug(inode, "failed with err %d\n", retval);
	if (retval <= 0)
		return retval;

	if (map->m_flags & EXT4_MAP_MAPPED) {
		ret = check_block_validity(inode, map);
		if (ret != 0)
			return ret;

		/*
		 * Inodes with freshly allocated blocks where contents will be
		 * visible after transaction commit must be on transaction's
		 * ordered data list.
		 */
		if (map->m_flags & EXT4_MAP_NEW &&
		    !(map->m_flags & EXT4_MAP_UNWRITTEN) &&
		    !(flags & EXT4_GET_BLOCKS_ZERO) &&
		    !ext4_is_quota_file(inode) &&
		    ext4_should_order_data(inode)) {
			loff_t start_byte = EXT4_LBLK_TO_B(inode, map->m_lblk);
			loff_t length = EXT4_LBLK_TO_B(inode, map->m_len);

			if (flags & EXT4_GET_BLOCKS_IO_SUBMIT)
				ret = ext4_jbd2_inode_add_wait(handle, inode,
						start_byte, length);
			else
				ret = ext4_jbd2_inode_add_write(handle, inode,
						start_byte, length);
			if (ret)
				return ret;
		}
	}
	ext4_fc_track_range(handle, inode, map->m_lblk, map->m_lblk +
			    map->m_len - 1);
	return retval;
}

/*
 * Update EXT4_MAP_FLAGS in bh->b_state. For buffer heads attached to pages
 * we have to be careful as someone else may be manipulating b_state as well.
 */
static void ext4_update_bh_state(struct buffer_head *bh, unsigned long flags)
{
	unsigned long old_state;
	unsigned long new_state;

	flags &= EXT4_MAP_FLAGS;

	/* Dummy buffer_head? Set non-atomically. */
	if (!bh->b_folio) {
		bh->b_state = (bh->b_state & ~EXT4_MAP_FLAGS) | flags;
		return;
	}
	/*
	 * Someone else may be modifying b_state. Be careful! This is ugly but
	 * once we get rid of using bh as a container for mapping information
	 * to pass to / from get_block functions, this can go away.
	 */
	old_state = READ_ONCE(bh->b_state);
	do {
		new_state = (old_state & ~EXT4_MAP_FLAGS) | flags;
	} while (unlikely(!try_cmpxchg(&bh->b_state, &old_state, new_state)));
}

/*
 * Make sure that the current journal transaction has enough credits to map
 * one extent. Return -EAGAIN if it cannot extend the current running
 * transaction.
 */
static inline int ext4_journal_ensure_extent_credits(handle_t *handle,
						     struct inode *inode)
{
	int credits;
	int ret;

	/* Called from ext4_da_write_begin() which has no handle started? */
	if (!handle)
		return 0;

	credits = ext4_chunk_trans_blocks(inode, 1);
	ret = __ext4_journal_ensure_credits(handle, credits, credits, 0);
	return ret <= 0 ? ret : -EAGAIN;
}

static int _ext4_get_block(struct inode *inode, sector_t iblock,
			   struct buffer_head *bh, int flags)
{
	struct ext4_map_blocks map;
	int ret = 0;

	if (ext4_has_inline_data(inode))
		return -ERANGE;

	map.m_lblk = iblock;
	map.m_len = bh->b_size >> inode->i_blkbits;

	ret = ext4_map_blocks(ext4_journal_current_handle(), inode, &map,
			      flags);
	if (ret > 0) {
		map_bh(bh, inode->i_sb, map.m_pblk);
		ext4_update_bh_state(bh, map.m_flags);
		bh->b_size = inode->i_sb->s_blocksize * map.m_len;
		ret = 0;
	} else if (ret == 0) {
		/* hole case, need to fill in bh->b_size */
		bh->b_size = inode->i_sb->s_blocksize * map.m_len;
	}
	return ret;
}

int ext4_get_block(struct inode *inode, sector_t iblock,
		   struct buffer_head *bh, int create)
{
	return _ext4_get_block(inode, iblock, bh,
			       create ? EXT4_GET_BLOCKS_CREATE : 0);
}

/*
 * Get block function used when preparing for buffered write if we require
 * creating an unwritten extent if blocks haven't been allocated.  The extent
 * will be converted to written after the IO is complete.
 */
int ext4_get_block_unwritten(struct inode *inode, sector_t iblock,
			     struct buffer_head *bh_result, int create)
{
	int ret = 0;

	ext4_debug("ext4_get_block_unwritten: inode %lu, create flag %d\n",
		   inode->i_ino, create);
	ret = _ext4_get_block(inode, iblock, bh_result,
			       EXT4_GET_BLOCKS_CREATE_UNWRIT_EXT);

	/*
	 * If the buffer is marked unwritten, mark it as new to make sure it is
	 * zeroed out correctly in case of partial writes. Otherwise, there is
	 * a chance of stale data getting exposed.
	 */
	if (ret == 0 && buffer_unwritten(bh_result))
		set_buffer_new(bh_result);

	return ret;
}

/* Maximum number of blocks we map for direct IO at once. */
#define DIO_MAX_BLOCKS 4096

/*
 * `handle' can be NULL if create is zero
 */
struct buffer_head *ext4_getblk(handle_t *handle, struct inode *inode,
				ext4_lblk_t block, int map_flags)
{
	struct ext4_map_blocks map;
	struct buffer_head *bh;
	int create = map_flags & EXT4_GET_BLOCKS_CREATE;
	bool nowait = map_flags & EXT4_GET_BLOCKS_CACHED_NOWAIT;
	int err;

	ASSERT((EXT4_SB(inode->i_sb)->s_mount_state & EXT4_FC_REPLAY)
		    || handle != NULL || create == 0);
	ASSERT(create == 0 || !nowait);

	map.m_lblk = block;
	map.m_len = 1;
	err = ext4_map_blocks(handle, inode, &map, map_flags);

	if (err == 0)
		return create ? ERR_PTR(-ENOSPC) : NULL;
	if (err < 0)
		return ERR_PTR(err);

	if (nowait)
		return sb_find_get_block(inode->i_sb, map.m_pblk);

	/*
	 * Since bh could introduce extra ref count such as referred by
	 * journal_head etc. Try to avoid using __GFP_MOVABLE here
	 * as it may fail the migration when journal_head remains.
	 */
	bh = getblk_unmovable(inode->i_sb->s_bdev, map.m_pblk,
				inode->i_sb->s_blocksize);

	if (unlikely(!bh))
		return ERR_PTR(-ENOMEM);
	if (map.m_flags & EXT4_MAP_NEW) {
		ASSERT(create != 0);
		ASSERT((EXT4_SB(inode->i_sb)->s_mount_state & EXT4_FC_REPLAY)
			    || (handle != NULL));

		/*
		 * Now that we do not always journal data, we should
		 * keep in mind whether this should always journal the
		 * new buffer as metadata.  For now, regular file
		 * writes use ext4_get_block instead, so it's not a
		 * problem.
		 */
		lock_buffer(bh);
		BUFFER_TRACE(bh, "call get_create_access");
		err = ext4_journal_get_create_access(handle, inode->i_sb, bh,
						     EXT4_JTR_NONE);
		if (unlikely(err)) {
			unlock_buffer(bh);
			goto errout;
		}
		if (!buffer_uptodate(bh)) {
			memset(bh->b_data, 0, inode->i_sb->s_blocksize);
			set_buffer_uptodate(bh);
		}
		unlock_buffer(bh);
		BUFFER_TRACE(bh, "call ext4_handle_dirty_metadata");
		err = ext4_handle_dirty_metadata(handle, inode, bh);
		if (unlikely(err))
			goto errout;
	} else
		BUFFER_TRACE(bh, "not a new buffer");
	return bh;
errout:
	brelse(bh);
	return ERR_PTR(err);
}

struct buffer_head *ext4_bread(handle_t *handle, struct inode *inode,
			       ext4_lblk_t block, int map_flags)
{
	struct buffer_head *bh;
	int ret;

	bh = ext4_getblk(handle, inode, block, map_flags);
	if (IS_ERR(bh))
		return bh;
	if (!bh || ext4_buffer_uptodate(bh))
		return bh;

	ret = ext4_read_bh_lock(bh, REQ_META | REQ_PRIO, true);
	if (ret) {
		put_bh(bh);
		return ERR_PTR(ret);
	}
	return bh;
}

/* Read a contiguous batch of blocks. */
int ext4_bread_batch(struct inode *inode, ext4_lblk_t block, int bh_count,
		     bool wait, struct buffer_head **bhs)
{
	int i, err;

	for (i = 0; i < bh_count; i++) {
		bhs[i] = ext4_getblk(NULL, inode, block + i, 0 /* map_flags */);
		if (IS_ERR(bhs[i])) {
			err = PTR_ERR(bhs[i]);
			bh_count = i;
			goto out_brelse;
		}
	}

	for (i = 0; i < bh_count; i++)
		/* Note that NULL bhs[i] is valid because of holes. */
		if (bhs[i] && !ext4_buffer_uptodate(bhs[i]))
			ext4_read_bh_lock(bhs[i], REQ_META | REQ_PRIO, false);

	if (!wait)
		return 0;

	for (i = 0; i < bh_count; i++)
		if (bhs[i])
			wait_on_buffer(bhs[i]);

	for (i = 0; i < bh_count; i++) {
		if (bhs[i] && !buffer_uptodate(bhs[i])) {
			err = -EIO;
			goto out_brelse;
		}
	}
	return 0;

out_brelse:
	for (i = 0; i < bh_count; i++) {
		brelse(bhs[i]);
		bhs[i] = NULL;
	}
	return err;
}

int ext4_walk_page_buffers(handle_t *handle, struct inode *inode,
			   struct buffer_head *head,
			   unsigned from,
			   unsigned to,
			   int *partial,
			   int (*fn)(handle_t *handle, struct inode *inode,
				     struct buffer_head *bh))
{
	struct buffer_head *bh;
	unsigned block_start, block_end;
	unsigned blocksize = head->b_size;
	int err, ret = 0;
	struct buffer_head *next;

	for (bh = head, block_start = 0;
	     ret == 0 && (bh != head || !block_start);
	     block_start = block_end, bh = next) {
		next = bh->b_this_page;
		block_end = block_start + blocksize;
		if (block_end <= from || block_start >= to) {
			if (partial && !buffer_uptodate(bh))
				*partial = 1;
			continue;
		}
		err = (*fn)(handle, inode, bh);
		if (!ret)
			ret = err;
	}
	return ret;
}

/*
 * Helper for handling dirtying of journalled data. We also mark the folio as
 * dirty so that writeback code knows about this page (and inode) contains
 * dirty data. ext4_writepages() then commits appropriate transaction to
 * make data stable.
 */
static int ext4_dirty_journalled_data(handle_t *handle, struct buffer_head *bh)
{
	struct folio *folio = bh->b_folio;
	struct inode *inode = folio->mapping->host;

	/* only regular files have a_ops */
	if (S_ISREG(inode->i_mode))
		folio_mark_dirty(folio);
	return ext4_handle_dirty_metadata(handle, NULL, bh);
}

int do_journal_get_write_access(handle_t *handle, struct inode *inode,
				struct buffer_head *bh)
{
	if (!buffer_mapped(bh) || buffer_freed(bh))
		return 0;
	BUFFER_TRACE(bh, "get write access");
	return ext4_journal_get_write_access(handle, inode->i_sb, bh,
					    EXT4_JTR_NONE);
}

int ext4_block_write_begin(handle_t *handle, struct folio *folio,
			   loff_t pos, unsigned len,
			   get_block_t *get_block)
{
	unsigned int from = offset_in_folio(folio, pos);
	unsigned to = from + len;
	struct inode *inode = folio->mapping->host;
	unsigned block_start, block_end;
	sector_t block;
	int err = 0;
	unsigned int blocksize = i_blocksize(inode);
	struct buffer_head *bh, *head, *wait[2];
	int nr_wait = 0;
	int i;
	bool should_journal_data = ext4_should_journal_data(inode);

	BUG_ON(!folio_test_locked(folio));
	BUG_ON(to > folio_size(folio));
	BUG_ON(from > to);
	WARN_ON_ONCE(blocksize > folio_size(folio));

	head = folio_buffers(folio);
	if (!head)
		head = create_empty_buffers(folio, blocksize, 0);
	block = EXT4_PG_TO_LBLK(inode, folio->index);

	for (bh = head, block_start = 0; bh != head || !block_start;
	    block++, block_start = block_end, bh = bh->b_this_page) {
		block_end = block_start + blocksize;
		if (block_end <= from || block_start >= to) {
			if (folio_test_uptodate(folio)) {
				set_buffer_uptodate(bh);
			}
			continue;
		}
		if (WARN_ON_ONCE(buffer_new(bh)))
			clear_buffer_new(bh);
		if (!buffer_mapped(bh)) {
			WARN_ON(bh->b_size != blocksize);
			err = ext4_journal_ensure_extent_credits(handle, inode);
			if (!err)
				err = get_block(inode, block, bh, 1);
			if (err)
				break;
			if (buffer_new(bh)) {
				/*
				 * We may be zeroing partial buffers or all new
				 * buffers in case of failure. Prepare JBD2 for
				 * that.
				 */
				if (should_journal_data)
					do_journal_get_write_access(handle,
								    inode, bh);
				if (folio_test_uptodate(folio)) {
					/*
					 * Unlike __block_write_begin() we leave
					 * dirtying of new uptodate buffers to
					 * ->write_end() time or
					 * folio_zero_new_buffers().
					 */
					set_buffer_uptodate(bh);
					continue;
				}
				if (block_end > to || block_start < from)
					folio_zero_segments(folio, to,
							    block_end,
							    block_start, from);
				continue;
			}
		}
		if (folio_test_uptodate(folio)) {
			set_buffer_uptodate(bh);
			continue;
		}
		if (!buffer_uptodate(bh) && !buffer_delay(bh) &&
		    !buffer_unwritten(bh) &&
		    (block_start < from || block_end > to)) {
			ext4_read_bh_lock(bh, 0, false);
			wait[nr_wait++] = bh;
		}
	}
	/*
	 * If we issued read requests, let them complete.
	 */
	for (i = 0; i < nr_wait; i++) {
		wait_on_buffer(wait[i]);
		if (!buffer_uptodate(wait[i]))
			err = -EIO;
	}
	if (unlikely(err)) {
		if (should_journal_data)
			ext4_journalled_zero_new_buffers(handle, inode, folio,
							 from, to);
		else
			folio_zero_new_buffers(folio, from, to);
	} else if (fscrypt_inode_uses_fs_layer_crypto(inode)) {
		for (i = 0; i < nr_wait; i++) {
			int err2;

			err2 = fscrypt_decrypt_pagecache_blocks(folio,
						blocksize, bh_offset(wait[i]));
			if (err2) {
				clear_buffer_uptodate(wait[i]);
				err = err2;
			}
		}
	}

	return err;
}

/*
 * To preserve ordering, it is essential that the hole instantiation and
 * the data write be encapsulated in a single transaction.  We cannot
 * close off a transaction and start a new one between the ext4_get_block()
 * and the ext4_write_end().  So doing the jbd2_journal_start at the start of
 * ext4_write_begin() is the right place.
 */
static int ext4_write_begin(const struct kiocb *iocb,
			    struct address_space *mapping,
			    loff_t pos, unsigned len,
			    struct folio **foliop, void **fsdata)
{
	struct inode *inode = mapping->host;
	int ret, needed_blocks;
	handle_t *handle;
	int retries = 0;
	struct folio *folio;
	pgoff_t index;
	unsigned from, to;

	ret = ext4_emergency_state(inode->i_sb);
	if (unlikely(ret))
		return ret;

	trace_ext4_write_begin(inode, pos, len);
	/*
	 * Reserve one block more for addition to orphan list in case
	 * we allocate blocks but write fails for some reason
	 */
	needed_blocks = ext4_chunk_trans_extent(inode,
			ext4_journal_blocks_per_folio(inode)) + 1;
	index = pos >> PAGE_SHIFT;

	if (ext4_test_inode_state(inode, EXT4_STATE_MAY_INLINE_DATA)) {
		ret = ext4_try_to_write_inline_data(mapping, inode, pos, len,
						    foliop);
		if (ret < 0)
			return ret;
		if (ret == 1)
			return 0;
	}

	/*
	 * write_begin_get_folio() can take a long time if the
	 * system is thrashing due to memory pressure, or if the folio
	 * is being written back.  So grab it first before we start
	 * the transaction handle.  This also allows us to allocate
	 * the folio (if needed) without using GFP_NOFS.
	 */
retry_grab:
	folio = write_begin_get_folio(iocb, mapping, index, len);
	if (IS_ERR(folio))
		return PTR_ERR(folio);

	if (len > folio_next_pos(folio) - pos)
		len = folio_next_pos(folio) - pos;

	from = offset_in_folio(folio, pos);
	to = from + len;

	/*
	 * The same as page allocation, we prealloc buffer heads before
	 * starting the handle.
	 */
	if (!folio_buffers(folio))
		create_empty_buffers(folio, inode->i_sb->s_blocksize, 0);

	folio_unlock(folio);

retry_journal:
	handle = ext4_journal_start(inode, EXT4_HT_WRITE_PAGE, needed_blocks);
	if (IS_ERR(handle)) {
		folio_put(folio);
		return PTR_ERR(handle);
	}

	folio_lock(folio);
	if (folio->mapping != mapping) {
		/* The folio got truncated from under us */
		folio_unlock(folio);
		folio_put(folio);
		ext4_journal_stop(handle);
		goto retry_grab;
	}
	/* In case writeback began while the folio was unlocked */
	folio_wait_stable(folio);

	if (ext4_should_dioread_nolock(inode))
		ret = ext4_block_write_begin(handle, folio, pos, len,
					     ext4_get_block_unwritten);
	else
		ret = ext4_block_write_begin(handle, folio, pos, len,
					     ext4_get_block);
	if (!ret && ext4_should_journal_data(inode)) {
		ret = ext4_walk_page_buffers(handle, inode,
					     folio_buffers(folio), from, to,
					     NULL, do_journal_get_write_access);
	}

	if (ret) {
		bool extended = (pos + len > inode->i_size) &&
				!ext4_verity_in_progress(inode);

		folio_unlock(folio);
		/*
		 * ext4_block_write_begin may have instantiated a few blocks
		 * outside i_size.  Trim these off again. Don't need
		 * i_size_read because we hold i_rwsem.
		 *
		 * Add inode to orphan list in case we crash before
		 * truncate finishes
		 */
		if (extended && ext4_can_truncate(inode))
			ext4_orphan_add(handle, inode);

		ext4_journal_stop(handle);
		if (extended) {
			ext4_truncate_failed_write(inode);
			/*
			 * If truncate failed early the inode might
			 * still be on the orphan list; we need to
			 * make sure the inode is removed from the
			 * orphan list in that case.
			 */
			if (inode->i_nlink)
				ext4_orphan_del(NULL, inode);
		}

		if (ret == -EAGAIN ||
		    (ret == -ENOSPC &&
		     ext4_should_retry_alloc(inode->i_sb, &retries)))
			goto retry_journal;
		folio_put(folio);
		return ret;
	}
	*foliop = folio;
	return ret;
}

/* For write_end() in data=journal mode */
static int write_end_fn(handle_t *handle, struct inode *inode,
			struct buffer_head *bh)
{
	int ret;
	if (!buffer_mapped(bh) || buffer_freed(bh))
		return 0;
	set_buffer_uptodate(bh);
	ret = ext4_dirty_journalled_data(handle, bh);
	clear_buffer_meta(bh);
	clear_buffer_prio(bh);
	clear_buffer_new(bh);
	return ret;
}

/*
 * We need to pick up the new inode size which generic_commit_write gave us
 * `iocb` can be NULL - eg, when called from page_symlink().
 *
 * ext4 never places buffers on inode->i_mapping->i_private_list.  metadata
 * buffers are managed internally.
 */
static int ext4_write_end(const struct kiocb *iocb,
			  struct address_space *mapping,
			  loff_t pos, unsigned len, unsigned copied,
			  struct folio *folio, void *fsdata)
{
	handle_t *handle = ext4_journal_current_handle();
	struct inode *inode = mapping->host;
	loff_t old_size = inode->i_size;
	int ret = 0, ret2;
	int i_size_changed = 0;
	bool verity = ext4_verity_in_progress(inode);

	trace_ext4_write_end(inode, pos, len, copied);

	if (ext4_has_inline_data(inode) &&
	    ext4_test_inode_state(inode, EXT4_STATE_MAY_INLINE_DATA))
		return ext4_write_inline_data_end(inode, pos, len, copied,
						  folio);

	copied = block_write_end(pos, len, copied, folio);
	/*
	 * it's important to update i_size while still holding folio lock:
	 * page writeout could otherwise come in and zero beyond i_size.
	 *
	 * If FS_IOC_ENABLE_VERITY is running on this inode, then Merkle tree
	 * blocks are being written past EOF, so skip the i_size update.
	 */
	if (!verity)
		i_size_changed = ext4_update_inode_size(inode, pos + copied);
	folio_unlock(folio);
	folio_put(folio);

	if (old_size < pos && !verity) {
		pagecache_isize_extended(inode, old_size, pos);
		ext4_zero_partial_blocks(handle, inode, old_size, pos - old_size);
	}
	/*
	 * Don't mark the inode dirty under folio lock. First, it unnecessarily
	 * makes the holding time of folio lock longer. Second, it forces lock
	 * ordering of folio lock and transaction start for journaling
	 * filesystems.
	 */
	if (i_size_changed)
		ret = ext4_mark_inode_dirty(handle, inode);

	if (pos + len > inode->i_size && !verity && ext4_can_truncate(inode))
		/* if we have allocated more blocks and copied
		 * less. We will have blocks allocated outside
		 * inode->i_size. So truncate them
		 */
		ext4_orphan_add(handle, inode);

	ret2 = ext4_journal_stop(handle);
	if (!ret)
		ret = ret2;

	if (pos + len > inode->i_size && !verity) {
		ext4_truncate_failed_write(inode);
		/*
		 * If truncate failed early the inode might still be
		 * on the orphan list; we need to make sure the inode
		 * is removed from the orphan list in that case.
		 */
		if (inode->i_nlink)
			ext4_orphan_del(NULL, inode);
	}

	return ret ? ret : copied;
}

/*
 * This is a private version of folio_zero_new_buffers() which doesn't
 * set the buffer to be dirty, since in data=journalled mode we need
 * to call ext4_dirty_journalled_data() instead.
 */
static void ext4_journalled_zero_new_buffers(handle_t *handle,
					    struct inode *inode,
					    struct folio *folio,
					    unsigned from, unsigned to)
{
	unsigned int block_start = 0, block_end;
	struct buffer_head *head, *bh;

	bh = head = folio_buffers(folio);
	do {
		block_end = block_start + bh->b_size;
		if (buffer_new(bh)) {
			if (block_end > from && block_start < to) {
				if (!folio_test_uptodate(folio)) {
					unsigned start, size;

					start = max(from, block_start);
					size = min(to, block_end) - start;

					folio_zero_range(folio, start, size);
				}
				clear_buffer_new(bh);
				write_end_fn(handle, inode, bh);
			}
		}
		block_start = block_end;
		bh = bh->b_this_page;
	} while (bh != head);
}

static int ext4_journalled_write_end(const struct kiocb *iocb,
				     struct address_space *mapping,
				     loff_t pos, unsigned len, unsigned copied,
				     struct folio *folio, void *fsdata)
{
	handle_t *handle = ext4_journal_current_handle();
	struct inode *inode = mapping->host;
	loff_t old_size = inode->i_size;
	int ret = 0, ret2;
	int partial = 0;
	unsigned from, to;
	int size_changed = 0;
	bool verity = ext4_verity_in_progress(inode);

	trace_ext4_journalled_write_end(inode, pos, len, copied);
	from = pos & (PAGE_SIZE - 1);
	to = from + len;

	BUG_ON(!ext4_handle_valid(handle));

	if (ext4_has_inline_data(inode))
		return ext4_write_inline_data_end(inode, pos, len, copied,
						  folio);

	if (unlikely(copied < len) && !folio_test_uptodate(folio)) {
		copied = 0;
		ext4_journalled_zero_new_buffers(handle, inode, folio,
						 from, to);
	} else {
		if (unlikely(copied < len))
			ext4_journalled_zero_new_buffers(handle, inode, folio,
							 from + copied, to);
		ret = ext4_walk_page_buffers(handle, inode,
					     folio_buffers(folio),
					     from, from + copied, &partial,
					     write_end_fn);
		if (!partial)
			folio_mark_uptodate(folio);
	}
	if (!verity)
		size_changed = ext4_update_inode_size(inode, pos + copied);
	EXT4_I(inode)->i_datasync_tid = handle->h_transaction->t_tid;
	folio_unlock(folio);
	folio_put(folio);

	if (old_size < pos && !verity) {
		pagecache_isize_extended(inode, old_size, pos);
		ext4_zero_partial_blocks(handle, inode, old_size, pos - old_size);
	}

	if (size_changed) {
		ret2 = ext4_mark_inode_dirty(handle, inode);
		if (!ret)
			ret = ret2;
	}

	if (pos + len > inode->i_size && !verity && ext4_can_truncate(inode))
		/* if we have allocated more blocks and copied
		 * less. We will have blocks allocated outside
		 * inode->i_size. So truncate them
		 */
		ext4_orphan_add(handle, inode);

	ret2 = ext4_journal_stop(handle);
	if (!ret)
		ret = ret2;
	if (pos + len > inode->i_size && !verity) {
		ext4_truncate_failed_write(inode);
		/*
		 * If truncate failed early the inode might still be
		 * on the orphan list; we need to make sure the inode
		 * is removed from the orphan list in that case.
		 */
		if (inode->i_nlink)
			ext4_orphan_del(NULL, inode);
	}

	return ret ? ret : copied;
}

/*
 * Reserve space for 'nr_resv' clusters
 */
static int ext4_da_reserve_space(struct inode *inode, int nr_resv)
{
	struct ext4_sb_info *sbi = EXT4_SB(inode->i_sb);
	struct ext4_inode_info *ei = EXT4_I(inode);
	int ret;

	/*
	 * We will charge metadata quota at writeout time; this saves
	 * us from metadata over-estimation, though we may go over by
	 * a small amount in the end.  Here we just reserve for data.
	 */
	ret = dquot_reserve_block(inode, EXT4_C2B(sbi, nr_resv));
	if (ret)
		return ret;

	spin_lock(&ei->i_block_reservation_lock);
	if (ext4_claim_free_clusters(sbi, nr_resv, 0)) {
		spin_unlock(&ei->i_block_reservation_lock);
		dquot_release_reservation_block(inode, EXT4_C2B(sbi, nr_resv));
		return -ENOSPC;
	}
	ei->i_reserved_data_blocks += nr_resv;
	trace_ext4_da_reserve_space(inode, nr_resv);
	spin_unlock(&ei->i_block_reservation_lock);

	return 0;       /* success */
}

void ext4_da_release_space(struct inode *inode, int to_free)
{
	struct ext4_sb_info *sbi = EXT4_SB(inode->i_sb);
	struct ext4_inode_info *ei = EXT4_I(inode);

	if (!to_free)
		return;		/* Nothing to release, exit */

	spin_lock(&EXT4_I(inode)->i_block_reservation_lock);

	trace_ext4_da_release_space(inode, to_free);
	if (unlikely(to_free > ei->i_reserved_data_blocks)) {
		/*
		 * if there aren't enough reserved blocks, then the
		 * counter is messed up somewhere.  Since this
		 * function is called from invalidate page, it's
		 * harmless to return without any action.
		 */
		ext4_warning(inode->i_sb, "ext4_da_release_space: "
			 "ino %lu, to_free %d with only %d reserved "
			 "data blocks", inode->i_ino, to_free,
			 ei->i_reserved_data_blocks);
		WARN_ON(1);
		to_free = ei->i_reserved_data_blocks;
	}
	ei->i_reserved_data_blocks -= to_free;

	/* update fs dirty data blocks counter */
	percpu_counter_sub(&sbi->s_dirtyclusters_counter, to_free);

	spin_unlock(&EXT4_I(inode)->i_block_reservation_lock);

	dquot_release_reservation_block(inode, EXT4_C2B(sbi, to_free));
}

/*
 * Delayed allocation stuff
 */

struct mpage_da_data {
	/* These are input fields for ext4_do_writepages() */
	struct inode *inode;
	struct writeback_control *wbc;
	unsigned int can_map:1;	/* Can writepages call map blocks? */

	/* These are internal state of ext4_do_writepages() */
	loff_t start_pos;	/* The start pos to write */
	loff_t next_pos;	/* Current pos to examine */
	loff_t end_pos;		/* Last pos to examine */

	/*
	 * Extent to map - this can be after start_pos because that can be
	 * fully mapped. We somewhat abuse m_flags to store whether the extent
	 * is delalloc or unwritten.
	 */
	struct ext4_map_blocks map;
	struct ext4_io_submit io_submit;	/* IO submission data */
	unsigned int do_map:1;
	unsigned int scanned_until_end:1;
	unsigned int journalled_more_data:1;
};

static void mpage_release_unused_pages(struct mpage_da_data *mpd,
				       bool invalidate)
{
	unsigned nr, i;
	pgoff_t index, end;
	struct folio_batch fbatch;
	struct inode *inode = mpd->inode;
	struct address_space *mapping = inode->i_mapping;

	/* This is necessary when next_pos == 0. */
	if (mpd->start_pos >= mpd->next_pos)
		return;

	mpd->scanned_until_end = 0;
	if (invalidate) {
		ext4_lblk_t start, last;
		start = EXT4_B_TO_LBLK(inode, mpd->start_pos);
		last = mpd->next_pos >> inode->i_blkbits;

		/*
		 * avoid racing with extent status tree scans made by
		 * ext4_insert_delayed_block()
		 */
		down_write(&EXT4_I(inode)->i_data_sem);
		ext4_es_remove_extent(inode, start, last - start);
		up_write(&EXT4_I(inode)->i_data_sem);
	}

	folio_batch_init(&fbatch);
	index = mpd->start_pos >> PAGE_SHIFT;
	end = mpd->next_pos >> PAGE_SHIFT;
	while (index < end) {
		nr = filemap_get_folios(mapping, &index, end - 1, &fbatch);
		if (nr == 0)
			break;
		for (i = 0; i < nr; i++) {
			struct folio *folio = fbatch.folios[i];

			if (folio_pos(folio) < mpd->start_pos)
				continue;
			if (folio_next_index(folio) > end)
				continue;
			BUG_ON(!folio_test_locked(folio));
			BUG_ON(folio_test_writeback(folio));
			if (invalidate) {
				if (folio_mapped(folio))
					folio_clear_dirty_for_io(folio);
				block_invalidate_folio(folio, 0,
						folio_size(folio));
				folio_clear_uptodate(folio);
			}
			folio_unlock(folio);
		}
		folio_batch_release(&fbatch);
	}
}

static void ext4_print_free_blocks(struct inode *inode)
{
	struct ext4_sb_info *sbi = EXT4_SB(inode->i_sb);
	struct super_block *sb = inode->i_sb;
	struct ext4_inode_info *ei = EXT4_I(inode);

	ext4_msg(sb, KERN_CRIT, "Total free blocks count %lld",
	       EXT4_C2B(EXT4_SB(inode->i_sb),
			ext4_count_free_clusters(sb)));
	ext4_msg(sb, KERN_CRIT, "Free/Dirty block details");
	ext4_msg(sb, KERN_CRIT, "free_blocks=%lld",
	       (long long) EXT4_C2B(EXT4_SB(sb),
		percpu_counter_sum(&sbi->s_freeclusters_counter)));
	ext4_msg(sb, KERN_CRIT, "dirty_blocks=%lld",
	       (long long) EXT4_C2B(EXT4_SB(sb),
		percpu_counter_sum(&sbi->s_dirtyclusters_counter)));
	ext4_msg(sb, KERN_CRIT, "Block reservation details");
	ext4_msg(sb, KERN_CRIT, "i_reserved_data_blocks=%u",
		 ei->i_reserved_data_blocks);
	return;
}

/*
 * Check whether the cluster containing lblk has been allocated or has
 * delalloc reservation.
 *
 * Returns 0 if the cluster doesn't have either, 1 if it has delalloc
 * reservation, 2 if it's already been allocated, negative error code on
 * failure.
 */
static int ext4_clu_alloc_state(struct inode *inode, ext4_lblk_t lblk)
{
	struct ext4_sb_info *sbi = EXT4_SB(inode->i_sb);
	int ret;

	/* Has delalloc reservation? */
	if (ext4_es_scan_clu(inode, &ext4_es_is_delayed, lblk))
		return 1;

	/* Already been allocated? */
	if (ext4_es_scan_clu(inode, &ext4_es_is_mapped, lblk))
		return 2;
	ret = ext4_clu_mapped(inode, EXT4_B2C(sbi, lblk));
	if (ret < 0)
		return ret;
	if (ret > 0)
		return 2;

	return 0;
}

/*
 * ext4_insert_delayed_blocks - adds a multiple delayed blocks to the extents
 *                              status tree, incrementing the reserved
 *                              cluster/block count or making pending
 *                              reservations where needed
 *
 * @inode - file containing the newly added block
 * @lblk - start logical block to be added
 * @len - length of blocks to be added
 *
 * Returns 0 on success, negative error code on failure.
 */
static int ext4_insert_delayed_blocks(struct inode *inode, ext4_lblk_t lblk,
				      ext4_lblk_t len)
{
	struct ext4_sb_info *sbi = EXT4_SB(inode->i_sb);
	int ret;
	bool lclu_allocated = false;
	bool end_allocated = false;
	ext4_lblk_t resv_clu;
	ext4_lblk_t end = lblk + len - 1;

	/*
	 * If the cluster containing lblk or end is shared with a delayed,
	 * written, or unwritten extent in a bigalloc file system, it's
	 * already been accounted for and does not need to be reserved.
	 * A pending reservation must be made for the cluster if it's
	 * shared with a written or unwritten extent and doesn't already
	 * have one.  Written and unwritten extents can be purged from the
	 * extents status tree if the system is under memory pressure, so
	 * it's necessary to examine the extent tree if a search of the
	 * extents status tree doesn't get a match.
	 */
	if (sbi->s_cluster_ratio == 1) {
		ret = ext4_da_reserve_space(inode, len);
		if (ret != 0)   /* ENOSPC */
			return ret;
	} else {   /* bigalloc */
		resv_clu = EXT4_B2C(sbi, end) - EXT4_B2C(sbi, lblk) + 1;

		ret = ext4_clu_alloc_state(inode, lblk);
		if (ret < 0)
			return ret;
		if (ret > 0) {
			resv_clu--;
			lclu_allocated = (ret == 2);
		}

		if (EXT4_B2C(sbi, lblk) != EXT4_B2C(sbi, end)) {
			ret = ext4_clu_alloc_state(inode, end);
			if (ret < 0)
				return ret;
			if (ret > 0) {
				resv_clu--;
				end_allocated = (ret == 2);
			}
		}

		if (resv_clu) {
			ret = ext4_da_reserve_space(inode, resv_clu);
			if (ret != 0)   /* ENOSPC */
				return ret;
		}
	}

	ext4_es_insert_delayed_extent(inode, lblk, len, lclu_allocated,
				      end_allocated);
	return 0;
}

/*
 * Looks up the requested blocks and sets the delalloc extent map.
 * First try to look up for the extent entry that contains the requested
 * blocks in the extent status tree without i_data_sem, then try to look
 * up for the ondisk extent mapping with i_data_sem in read mode,
 * finally hold i_data_sem in write mode, looks up again and add a
 * delalloc extent entry if it still couldn't find any extent. Pass out
 * the mapped extent through @map and return 0 on success.
 */
static int ext4_da_map_blocks(struct inode *inode, struct ext4_map_blocks *map)
{
	struct extent_status es;
	int retval;
#ifdef ES_AGGRESSIVE_TEST
	struct ext4_map_blocks orig_map;

	memcpy(&orig_map, map, sizeof(*map));
#endif

	map->m_flags = 0;
	ext_debug(inode, "max_blocks %u, logical block %lu\n", map->m_len,
		  (unsigned long) map->m_lblk);

	ext4_check_map_extents_env(inode);

	/* Lookup extent status tree firstly */
	if (ext4_es_lookup_extent(inode, map->m_lblk, NULL, &es, NULL)) {
		map->m_len = min_t(unsigned int, map->m_len,
				   es.es_len - (map->m_lblk - es.es_lblk));

		if (ext4_es_is_hole(&es))
			goto add_delayed;

found:
		/*
		 * Delayed extent could be allocated by fallocate.
		 * So we need to check it.
		 */
		if (ext4_es_is_delayed(&es)) {
			map->m_flags |= EXT4_MAP_DELAYED;
			return 0;
		}

		map->m_pblk = ext4_es_pblock(&es) + map->m_lblk - es.es_lblk;
		if (ext4_es_is_written(&es))
			map->m_flags |= EXT4_MAP_MAPPED;
		else if (ext4_es_is_unwritten(&es))
			map->m_flags |= EXT4_MAP_UNWRITTEN;
		else
			BUG();

#ifdef ES_AGGRESSIVE_TEST
		ext4_map_blocks_es_recheck(NULL, inode, map, &orig_map, 0);
#endif
		return 0;
	}

	/*
	 * Try to see if we can get the block without requesting a new
	 * file system block.
	 */
	down_read(&EXT4_I(inode)->i_data_sem);
	if (ext4_has_inline_data(inode))
		retval = 0;
	else
		retval = ext4_map_query_blocks(NULL, inode, map, 0);
	up_read(&EXT4_I(inode)->i_data_sem);
	if (retval)
		return retval < 0 ? retval : 0;

add_delayed:
	down_write(&EXT4_I(inode)->i_data_sem);
	/*
	 * Page fault path (ext4_page_mkwrite does not take i_rwsem)
	 * and fallocate path (no folio lock) can race. Make sure we
	 * lookup the extent status tree here again while i_data_sem
	 * is held in write mode, before inserting a new da entry in
	 * the extent status tree.
	 */
	if (ext4_es_lookup_extent(inode, map->m_lblk, NULL, &es, NULL)) {
		map->m_len = min_t(unsigned int, map->m_len,
				   es.es_len - (map->m_lblk - es.es_lblk));

		if (!ext4_es_is_hole(&es)) {
			up_write(&EXT4_I(inode)->i_data_sem);
			goto found;
		}
	} else if (!ext4_has_inline_data(inode)) {
		retval = ext4_map_query_blocks(NULL, inode, map, 0);
		if (retval) {
			up_write(&EXT4_I(inode)->i_data_sem);
			return retval < 0 ? retval : 0;
		}
	}

	map->m_flags |= EXT4_MAP_DELAYED;
	retval = ext4_insert_delayed_blocks(inode, map->m_lblk, map->m_len);
	if (!retval)
		map->m_seq = READ_ONCE(EXT4_I(inode)->i_es_seq);
	up_write(&EXT4_I(inode)->i_data_sem);

	return retval;
}

/*
 * This is a special get_block_t callback which is used by
 * ext4_da_write_begin().  It will either return mapped block or
 * reserve space for a single block.
 *
 * For delayed buffer_head we have BH_Mapped, BH_New, BH_Delay set.
 * We also have b_blocknr = -1 and b_bdev initialized properly
 *
 * For unwritten buffer_head we have BH_Mapped, BH_New, BH_Unwritten set.
 * We also have b_blocknr = physicalblock mapping unwritten extent and b_bdev
 * initialized properly.
 */
int ext4_da_get_block_prep(struct inode *inode, sector_t iblock,
			   struct buffer_head *bh, int create)
{
	struct ext4_map_blocks map;
	sector_t invalid_block = ~((sector_t) 0xffff);
	int ret = 0;

	BUG_ON(create == 0);
	BUG_ON(bh->b_size != inode->i_sb->s_blocksize);

	if (invalid_block < ext4_blocks_count(EXT4_SB(inode->i_sb)->s_es))
		invalid_block = ~0;

	map.m_lblk = iblock;
	map.m_len = 1;

	/*
	 * first, we need to know whether the block is allocated already
	 * preallocated blocks are unmapped but should treated
	 * the same as allocated blocks.
	 */
	ret = ext4_da_map_blocks(inode, &map);
	if (ret < 0)
		return ret;

	if (map.m_flags & EXT4_MAP_DELAYED) {
		map_bh(bh, inode->i_sb, invalid_block);
		set_buffer_new(bh);
		set_buffer_delay(bh);
		return 0;
	}

	map_bh(bh, inode->i_sb, map.m_pblk);
	ext4_update_bh_state(bh, map.m_flags);

	if (buffer_unwritten(bh)) {
		/* A delayed write to unwritten bh should be marked
		 * new and mapped.  Mapped ensures that we don't do
		 * get_block multiple times when we write to the same
		 * offset and new ensures that we do proper zero out
		 * for partial write.
		 */
		set_buffer_new(bh);
		set_buffer_mapped(bh);
	}
	return 0;
}

static void mpage_folio_done(struct mpage_da_data *mpd, struct folio *folio)
{
	mpd->start_pos += folio_size(folio);
	mpd->wbc->nr_to_write -= folio_nr_pages(folio);
	folio_unlock(folio);
}

static int mpage_submit_folio(struct mpage_da_data *mpd, struct folio *folio)
{
	size_t len;
	loff_t size;
	int err;

	WARN_ON_ONCE(folio_pos(folio) != mpd->start_pos);
	folio_clear_dirty_for_io(folio);
	/*
	 * We have to be very careful here!  Nothing protects writeback path
	 * against i_size changes and the page can be writeably mapped into
	 * page tables. So an application can be growing i_size and writing
	 * data through mmap while writeback runs. folio_clear_dirty_for_io()
	 * write-protects our page in page tables and the page cannot get
	 * written to again until we release folio lock. So only after
	 * folio_clear_dirty_for_io() we are safe to sample i_size for
	 * ext4_bio_write_folio() to zero-out tail of the written page. We rely
	 * on the barrier provided by folio_test_clear_dirty() in
	 * folio_clear_dirty_for_io() to make sure i_size is really sampled only
	 * after page tables are updated.
	 */
	size = i_size_read(mpd->inode);
	len = folio_size(folio);
	if (folio_pos(folio) + len > size &&
	    !ext4_verity_in_progress(mpd->inode))
		len = size & (len - 1);
	err = ext4_bio_write_folio(&mpd->io_submit, folio, len);

	return err;
}

#define BH_FLAGS (BIT(BH_Unwritten) | BIT(BH_Delay))

/*
 * mballoc gives us at most this number of blocks...
 * XXX: That seems to be only a limitation of ext4_mb_normalize_request().
 * The rest of mballoc seems to handle chunks up to full group size.
 */
#define MAX_WRITEPAGES_EXTENT_LEN 2048

/*
 * mpage_add_bh_to_extent - try to add bh to extent of blocks to map
 *
 * @mpd - extent of blocks
 * @lblk - logical number of the block in the file
 * @bh - buffer head we want to add to the extent
 *
 * The function is used to collect contig. blocks in the same state. If the
 * buffer doesn't require mapping for writeback and we haven't started the
 * extent of buffers to map yet, the function returns 'true' immediately - the
 * caller can write the buffer right away. Otherwise the function returns true
 * if the block has been added to the extent, false if the block couldn't be
 * added.
 */
static bool mpage_add_bh_to_extent(struct mpage_da_data *mpd, ext4_lblk_t lblk,
				   struct buffer_head *bh)
{
	struct ext4_map_blocks *map = &mpd->map;

	/* Buffer that doesn't need mapping for writeback? */
	if (!buffer_dirty(bh) || !buffer_mapped(bh) ||
	    (!buffer_delay(bh) && !buffer_unwritten(bh))) {
		/* So far no extent to map => we write the buffer right away */
		if (map->m_len == 0)
			return true;
		return false;
	}

	/* First block in the extent? */
	if (map->m_len == 0) {
		/* We cannot map unless handle is started... */
		if (!mpd->do_map)
			return false;
		map->m_lblk = lblk;
		map->m_len = 1;
		map->m_flags = bh->b_state & BH_FLAGS;
		return true;
	}

	/* Don't go larger than mballoc is willing to allocate */
	if (map->m_len >= MAX_WRITEPAGES_EXTENT_LEN)
		return false;

	/* Can we merge the block to our big extent? */
	if (lblk == map->m_lblk + map->m_len &&
	    (bh->b_state & BH_FLAGS) == map->m_flags) {
		map->m_len++;
		return true;
	}
	return false;
}

/*
 * mpage_process_page_bufs - submit page buffers for IO or add them to extent
 *
 * @mpd - extent of blocks for mapping
 * @head - the first buffer in the page
 * @bh - buffer we should start processing from
 * @lblk - logical number of the block in the file corresponding to @bh
 *
 * Walk through page buffers from @bh upto @head (exclusive) and either submit
 * the page for IO if all buffers in this page were mapped and there's no
 * accumulated extent of buffers to map or add buffers in the page to the
 * extent of buffers to map. The function returns 1 if the caller can continue
 * by processing the next page, 0 if it should stop adding buffers to the
 * extent to map because we cannot extend it anymore. It can also return value
 * < 0 in case of error during IO submission.
 */
static int mpage_process_page_bufs(struct mpage_da_data *mpd,
				   struct buffer_head *head,
				   struct buffer_head *bh,
				   ext4_lblk_t lblk)
{
	struct inode *inode = mpd->inode;
	int err;
	ext4_lblk_t blocks = (i_size_read(inode) + i_blocksize(inode) - 1)
							>> inode->i_blkbits;

	if (ext4_verity_in_progress(inode))
		blocks = EXT_MAX_BLOCKS;

	do {
		BUG_ON(buffer_locked(bh));

		if (lblk >= blocks || !mpage_add_bh_to_extent(mpd, lblk, bh)) {
			/* Found extent to map? */
			if (mpd->map.m_len)
				return 0;
			/* Buffer needs mapping and handle is not started? */
			if (!mpd->do_map)
				return 0;
			/* Everything mapped so far and we hit EOF */
			break;
		}
	} while (lblk++, (bh = bh->b_this_page) != head);
	/* So far everything mapped? Submit the page for IO. */
	if (mpd->map.m_len == 0) {
		err = mpage_submit_folio(mpd, head->b_folio);
		if (err < 0)
			return err;
		mpage_folio_done(mpd, head->b_folio);
	}
	if (lblk >= blocks) {
		mpd->scanned_until_end = 1;
		return 0;
	}
	return 1;
}

/*
 * mpage_process_folio - update folio buffers corresponding to changed extent
 *			 and may submit fully mapped page for IO
 * @mpd: description of extent to map, on return next extent to map
 * @folio: Contains these buffers.
 * @m_lblk: logical block mapping.
 * @m_pblk: corresponding physical mapping.
 * @map_bh: determines on return whether this page requires any further
 *		  mapping or not.
 *
 * Scan given folio buffers corresponding to changed extent and update buffer
 * state according to new extent state.
 * We map delalloc buffers to their physical location, clear unwritten bits.
 * If the given folio is not fully mapped, we update @mpd to the next extent in
 * the given folio that needs mapping & return @map_bh as true.
 */
static int mpage_process_folio(struct mpage_da_data *mpd, struct folio *folio,
			      ext4_lblk_t *m_lblk, ext4_fsblk_t *m_pblk,
			      bool *map_bh)
{
	struct buffer_head *head, *bh;
	ext4_io_end_t *io_end = mpd->io_submit.io_end;
	ext4_lblk_t lblk = *m_lblk;
	ext4_fsblk_t pblock = *m_pblk;
	int err = 0;
	ssize_t io_end_size = 0;
	struct ext4_io_end_vec *io_end_vec = ext4_last_io_end_vec(io_end);

	bh = head = folio_buffers(folio);
	do {
		if (lblk < mpd->map.m_lblk)
			continue;
		if (lblk >= mpd->map.m_lblk + mpd->map.m_len) {
			/*
			 * Buffer after end of mapped extent.
			 * Find next buffer in the folio to map.
			 */
			mpd->map.m_len = 0;
			mpd->map.m_flags = 0;
			io_end_vec->size += io_end_size;

			err = mpage_process_page_bufs(mpd, head, bh, lblk);
			if (err > 0)
				err = 0;
			if (!err && mpd->map.m_len && mpd->map.m_lblk > lblk) {
				io_end_vec = ext4_alloc_io_end_vec(io_end);
				if (IS_ERR(io_end_vec)) {
					err = PTR_ERR(io_end_vec);
					goto out;
				}
				io_end_vec->offset = EXT4_LBLK_TO_B(mpd->inode,
								mpd->map.m_lblk);
			}
			*map_bh = true;
			goto out;
		}
		if (buffer_delay(bh)) {
			clear_buffer_delay(bh);
			bh->b_blocknr = pblock++;
		}
		clear_buffer_unwritten(bh);
		io_end_size += i_blocksize(mpd->inode);
	} while (lblk++, (bh = bh->b_this_page) != head);

	io_end_vec->size += io_end_size;
	*map_bh = false;
out:
	*m_lblk = lblk;
	*m_pblk = pblock;
	return err;
}

/*
 * mpage_map_buffers - update buffers corresponding to changed extent and
 *		       submit fully mapped pages for IO
 *
 * @mpd - description of extent to map, on return next extent to map
 *
 * Scan buffers corresponding to changed extent (we expect corresponding pages
 * to be already locked) and update buffer state according to new extent state.
 * We map delalloc buffers to their physical location, clear unwritten bits,
 * and mark buffers as uninit when we perform writes to unwritten extents
 * and do extent conversion after IO is finished. If the last page is not fully
 * mapped, we update @map to the next extent in the last page that needs
 * mapping. Otherwise we submit the page for IO.
 */
static int mpage_map_and_submit_buffers(struct mpage_da_data *mpd)
{
	struct folio_batch fbatch;
	unsigned nr, i;
	struct inode *inode = mpd->inode;
	pgoff_t start, end;
	ext4_lblk_t lblk;
	ext4_fsblk_t pblock;
	int err;
	bool map_bh = false;

	start = EXT4_LBLK_TO_PG(inode, mpd->map.m_lblk);
	end = EXT4_LBLK_TO_PG(inode, mpd->map.m_lblk + mpd->map.m_len - 1);
	pblock = mpd->map.m_pblk;

	folio_batch_init(&fbatch);
	while (start <= end) {
		nr = filemap_get_folios(inode->i_mapping, &start, end, &fbatch);
		if (nr == 0)
			break;
		for (i = 0; i < nr; i++) {
			struct folio *folio = fbatch.folios[i];

			lblk = EXT4_PG_TO_LBLK(inode, folio->index);
			err = mpage_process_folio(mpd, folio, &lblk, &pblock,
						 &map_bh);
			/*
			 * If map_bh is true, means page may require further bh
			 * mapping, or maybe the page was submitted for IO.
			 * So we return to call further extent mapping.
			 */
			if (err < 0 || map_bh)
				goto out;
			/* Page fully mapped - let IO run! */
			err = mpage_submit_folio(mpd, folio);
			if (err < 0)
				goto out;
			mpage_folio_done(mpd, folio);
		}
		folio_batch_release(&fbatch);
	}
	/* Extent fully mapped and matches with page boundary. We are done. */
	mpd->map.m_len = 0;
	mpd->map.m_flags = 0;
	return 0;
out:
	folio_batch_release(&fbatch);
	return err;
}

static int mpage_map_one_extent(handle_t *handle, struct mpage_da_data *mpd)
{
	struct inode *inode = mpd->inode;
	struct ext4_map_blocks *map = &mpd->map;
	int get_blocks_flags;
	int err, dioread_nolock;

	/* Make sure transaction has enough credits for this extent */
	err = ext4_journal_ensure_extent_credits(handle, inode);
	if (err < 0)
		return err;

	trace_ext4_da_write_pages_extent(inode, map);
	/*
	 * Call ext4_map_blocks() to allocate any delayed allocation blocks, or
	 * to convert an unwritten extent to be initialized (in the case
	 * where we have written into one or more preallocated blocks).  It is
	 * possible that we're going to need more metadata blocks than
	 * previously reserved. However we must not fail because we're in
	 * writeback and there is nothing we can do about it so it might result
	 * in data loss.  So use reserved blocks to allocate metadata if
	 * possible. In addition, do not cache any unrelated extents, as it
	 * only holds the folio lock but does not hold the i_rwsem or
	 * invalidate_lock, which could corrupt the extent status tree.
	 */
	get_blocks_flags = EXT4_GET_BLOCKS_CREATE |
			   EXT4_GET_BLOCKS_METADATA_NOFAIL |
			   EXT4_GET_BLOCKS_IO_SUBMIT |
			   EXT4_EX_NOCACHE;

	dioread_nolock = ext4_should_dioread_nolock(inode);
	if (dioread_nolock)
		get_blocks_flags |= EXT4_GET_BLOCKS_UNWRIT_EXT;

	err = ext4_map_blocks(handle, inode, map, get_blocks_flags);
	if (err < 0)
		return err;
	if (dioread_nolock && (map->m_flags & EXT4_MAP_UNWRITTEN)) {
		if (!mpd->io_submit.io_end->handle &&
		    ext4_handle_valid(handle)) {
			mpd->io_submit.io_end->handle = handle->h_rsv_handle;
			handle->h_rsv_handle = NULL;
		}
		ext4_set_io_unwritten_flag(mpd->io_submit.io_end);
	}

	BUG_ON(map->m_len == 0);
	return 0;
}

/*
 * This is used to submit mapped buffers in a single folio that is not fully
 * mapped for various reasons, such as insufficient space or journal credits.
 */
static int mpage_submit_partial_folio(struct mpage_da_data *mpd)
{
	struct inode *inode = mpd->inode;
	struct folio *folio;
	loff_t pos;
	int ret;

	folio = filemap_get_folio(inode->i_mapping,
				  mpd->start_pos >> PAGE_SHIFT);
	if (IS_ERR(folio))
		return PTR_ERR(folio);
	/*
	 * The mapped position should be within the current processing folio
	 * but must not be the folio start position.
	 */
	pos = ((loff_t)mpd->map.m_lblk) << inode->i_blkbits;
	if (WARN_ON_ONCE((folio_pos(folio) == pos) ||
			 !folio_contains(folio, pos >> PAGE_SHIFT)))
		return -EINVAL;

	ret = mpage_submit_folio(mpd, folio);
	if (ret)
		goto out;
	/*
	 * Update start_pos to prevent this folio from being released in
	 * mpage_release_unused_pages(), it will be reset to the aligned folio
	 * pos when this folio is written again in the next round. Additionally,
	 * do not update wbc->nr_to_write here, as it will be updated once the
	 * entire folio has finished processing.
	 */
	mpd->start_pos = pos;
out:
	folio_unlock(folio);
	folio_put(folio);
	return ret;
}

/*
 * mpage_map_and_submit_extent - map extent starting at mpd->lblk of length
 *				 mpd->len and submit pages underlying it for IO
 *
 * @handle - handle for journal operations
 * @mpd - extent to map
 * @give_up_on_write - we set this to true iff there is a fatal error and there
 *                     is no hope of writing the data. The caller should discard
 *                     dirty pages to avoid infinite loops.
 *
 * The function maps extent starting at mpd->lblk of length mpd->len. If it is
 * delayed, blocks are allocated, if it is unwritten, we may need to convert
 * them to initialized or split the described range from larger unwritten
 * extent. Note that we need not map all the described range since allocation
 * can return less blocks or the range is covered by more unwritten extents. We
 * cannot map more because we are limited by reserved transaction credits. On
 * the other hand we always make sure that the last touched page is fully
 * mapped so that it can be written out (and thus forward progress is
 * guaranteed). After mapping we submit all mapped pages for IO.
 */
static int mpage_map_and_submit_extent(handle_t *handle,
				       struct mpage_da_data *mpd,
				       bool *give_up_on_write)
{
	struct inode *inode = mpd->inode;
	struct ext4_map_blocks *map = &mpd->map;
	int err;
	loff_t disksize;
	int progress = 0;
	ext4_io_end_t *io_end = mpd->io_submit.io_end;
	struct ext4_io_end_vec *io_end_vec;

	io_end_vec = ext4_alloc_io_end_vec(io_end);
	if (IS_ERR(io_end_vec))
		return PTR_ERR(io_end_vec);
	io_end_vec->offset = EXT4_LBLK_TO_B(inode, map->m_lblk);
	do {
		err = mpage_map_one_extent(handle, mpd);
		if (err < 0) {
			struct super_block *sb = inode->i_sb;

			if (ext4_emergency_state(sb))
				goto invalidate_dirty_pages;
			/*
			 * Let the uper layers retry transient errors.
			 * In the case of ENOSPC, if ext4_count_free_blocks()
			 * is non-zero, a commit should free up blocks.
			 */
			if ((err == -ENOMEM) || (err == -EAGAIN) ||
			    (err == -ENOSPC && ext4_count_free_clusters(sb))) {
				/*
				 * We may have already allocated extents for
				 * some bhs inside the folio, issue the
				 * corresponding data to prevent stale data.
				 */
				if (progress) {
					if (mpage_submit_partial_folio(mpd))
						goto invalidate_dirty_pages;
					goto update_disksize;
				}
				return err;
			}
			ext4_msg(sb, KERN_CRIT,
				 "Delayed block allocation failed for "
				 "inode %lu at logical offset %llu with"
				 " max blocks %u with error %d",
				 inode->i_ino,
				 (unsigned long long)map->m_lblk,
				 (unsigned)map->m_len, -err);
			ext4_msg(sb, KERN_CRIT,
				 "This should not happen!! Data will "
				 "be lost\n");
			if (err == -ENOSPC)
				ext4_print_free_blocks(inode);
		invalidate_dirty_pages:
			*give_up_on_write = true;
			return err;
		}
		progress = 1;
		/*
		 * Update buffer state, submit mapped pages, and get us new
		 * extent to map
		 */
		err = mpage_map_and_submit_buffers(mpd);
		if (err < 0)
			goto update_disksize;
	} while (map->m_len);

update_disksize:
	/*
	 * Update on-disk size after IO is submitted.  Races with
	 * truncate are avoided by checking i_size under i_data_sem.
	 */
	disksize = mpd->start_pos;
	if (disksize > READ_ONCE(EXT4_I(inode)->i_disksize)) {
		int err2;
		loff_t i_size;

		down_write(&EXT4_I(inode)->i_data_sem);
		i_size = i_size_read(inode);
		if (disksize > i_size)
			disksize = i_size;
		if (disksize > EXT4_I(inode)->i_disksize)
			EXT4_I(inode)->i_disksize = disksize;
		up_write(&EXT4_I(inode)->i_data_sem);
		err2 = ext4_mark_inode_dirty(handle, inode);
		if (err2) {
			ext4_error_err(inode->i_sb, -err2,
				       "Failed to mark inode %lu dirty",
				       inode->i_ino);
		}
		if (!err)
			err = err2;
	}
	return err;
}

static int ext4_journal_folio_buffers(handle_t *handle, struct folio *folio,
				     size_t len)
{
	struct buffer_head *page_bufs = folio_buffers(folio);
	struct inode *inode = folio->mapping->host;
	int ret, err;

	ret = ext4_walk_page_buffers(handle, inode, page_bufs, 0, len,
				     NULL, do_journal_get_write_access);
	err = ext4_walk_page_buffers(handle, inode, page_bufs, 0, len,
				     NULL, write_end_fn);
	if (ret == 0)
		ret = err;
	err = ext4_jbd2_inode_add_write(handle, inode, folio_pos(folio), len);
	if (ret == 0)
		ret = err;
	EXT4_I(inode)->i_datasync_tid = handle->h_transaction->t_tid;

	return ret;
}

static int mpage_journal_page_buffers(handle_t *handle,
				      struct mpage_da_data *mpd,
				      struct folio *folio)
{
	struct inode *inode = mpd->inode;
	loff_t size = i_size_read(inode);
	size_t len = folio_size(folio);

	folio_clear_checked(folio);
	mpd->wbc->nr_to_write -= folio_nr_pages(folio);

	if (folio_pos(folio) + len > size &&
	    !ext4_verity_in_progress(inode))
		len = size & (len - 1);

	return ext4_journal_folio_buffers(handle, folio, len);
}

/*
 * mpage_prepare_extent_to_map - find & lock contiguous range of dirty pages
 * 				 needing mapping, submit mapped pages
 *
 * @mpd - where to look for pages
 *
 * Walk dirty pages in the mapping. If they are fully mapped, submit them for
 * IO immediately. If we cannot map blocks, we submit just already mapped
 * buffers in the page for IO and keep page dirty. When we can map blocks and
 * we find a page which isn't mapped we start accumulating extent of buffers
 * underlying these pages that needs mapping (formed by either delayed or
 * unwritten buffers). We also lock the pages containing these buffers. The
 * extent found is returned in @mpd structure (starting at mpd->lblk with
 * length mpd->len blocks).
 *
 * Note that this function can attach bios to one io_end structure which are
 * neither logically nor physically contiguous. Although it may seem as an
 * unnecessary complication, it is actually inevitable in blocksize < pagesize
 * case as we need to track IO to all buffers underlying a page in one io_end.
 */
static int mpage_prepare_extent_to_map(struct mpage_da_data *mpd)
{
	struct address_space *mapping = mpd->inode->i_mapping;
	struct folio_batch fbatch;
	unsigned int nr_folios;
	pgoff_t index = mpd->start_pos >> PAGE_SHIFT;
	pgoff_t end = mpd->end_pos >> PAGE_SHIFT;
	xa_mark_t tag;
	int i, err = 0;
	ext4_lblk_t lblk;
	struct buffer_head *head;
	handle_t *handle = NULL;
	int bpp = ext4_journal_blocks_per_folio(mpd->inode);

	tag = wbc_to_tag(mpd->wbc);

	mpd->map.m_len = 0;
	mpd->next_pos = mpd->start_pos;
	if (ext4_should_journal_data(mpd->inode)) {
		handle = ext4_journal_start(mpd->inode, EXT4_HT_WRITE_PAGE,
					    bpp);
		if (IS_ERR(handle))
			return PTR_ERR(handle);
	}
	folio_batch_init(&fbatch);
	while (index <= end) {
		nr_folios = filemap_get_folios_tag(mapping, &index, end,
				tag, &fbatch);
		if (nr_folios == 0)
			break;

		for (i = 0; i < nr_folios; i++) {
			struct folio *folio = fbatch.folios[i];

			/*
			 * Accumulated enough dirty pages? This doesn't apply
			 * to WB_SYNC_ALL mode. For integrity sync we have to
			 * keep going because someone may be concurrently
			 * dirtying pages, and we might have synced a lot of
			 * newly appeared dirty pages, but have not synced all
			 * of the old dirty pages.
			 */
			if (mpd->wbc->sync_mode == WB_SYNC_NONE &&
			    mpd->wbc->nr_to_write <=
			    EXT4_LBLK_TO_PG(mpd->inode, mpd->map.m_len))
				goto out;

			/* If we can't merge this page, we are done. */
			if (mpd->map.m_len > 0 &&
			    mpd->next_pos != folio_pos(folio))
				goto out;

			if (handle) {
				err = ext4_journal_ensure_credits(handle, bpp,
								  0);
				if (err < 0)
					goto out;
			}

			folio_lock(folio);
			/*
			 * If the page is no longer dirty, or its mapping no
			 * longer corresponds to inode we are writing (which
			 * means it has been truncated or invalidated), or the
			 * page is already under writeback and we are not doing
			 * a data integrity writeback, skip the page
			 */
			if (!folio_test_dirty(folio) ||
			    (folio_test_writeback(folio) &&
			     (mpd->wbc->sync_mode == WB_SYNC_NONE)) ||
			    unlikely(folio->mapping != mapping)) {
				folio_unlock(folio);
				continue;
			}

			folio_wait_writeback(folio);
			BUG_ON(folio_test_writeback(folio));

			/*
			 * Should never happen but for buggy code in
			 * other subsystems that call
			 * set_page_dirty() without properly warning
			 * the file system first.  See [1] for more
			 * information.
			 *
			 * [1] https://lore.kernel.org/linux-mm/20180103100430.GE4911@quack2.suse.cz
			 */
			if (!folio_buffers(folio)) {
				ext4_warning_inode(mpd->inode, "page %lu does not have buffers attached", folio->index);
				folio_clear_dirty(folio);
				folio_unlock(folio);
				continue;
			}

			if (mpd->map.m_len == 0)
				mpd->start_pos = folio_pos(folio);
			mpd->next_pos = folio_next_pos(folio);
			/*
			 * Writeout when we cannot modify metadata is simple.
			 * Just submit the page. For data=journal mode we
			 * first handle writeout of the page for checkpoint and
			 * only after that handle delayed page dirtying. This
			 * makes sure current data is checkpointed to the final
			 * location before possibly journalling it again which
			 * is desirable when the page is frequently dirtied
			 * through a pin.
			 */
			if (!mpd->can_map) {
				err = mpage_submit_folio(mpd, folio);
				if (err < 0)
					goto out;
				/* Pending dirtying of journalled data? */
				if (folio_test_checked(folio)) {
					err = mpage_journal_page_buffers(handle,
						mpd, folio);
					if (err < 0)
						goto out;
					mpd->journalled_more_data = 1;
				}
				mpage_folio_done(mpd, folio);
			} else {
				/* Add all dirty buffers to mpd */
				lblk = EXT4_PG_TO_LBLK(mpd->inode, folio->index);
				head = folio_buffers(folio);
				err = mpage_process_page_bufs(mpd, head, head,
						lblk);
				if (err <= 0)
					goto out;
				err = 0;
			}
		}
		folio_batch_release(&fbatch);
		cond_resched();
	}
	mpd->scanned_until_end = 1;
	if (handle)
		ext4_journal_stop(handle);
	return 0;
out:
	folio_batch_release(&fbatch);
	if (handle)
		ext4_journal_stop(handle);
	return err;
}

static int ext4_do_writepages(struct mpage_da_data *mpd)
{
	struct writeback_control *wbc = mpd->wbc;
	pgoff_t	writeback_index = 0;
	long nr_to_write = wbc->nr_to_write;
	int range_whole = 0;
	int cycled = 1;
	handle_t *handle = NULL;
	struct inode *inode = mpd->inode;
	struct address_space *mapping = inode->i_mapping;
	int needed_blocks, rsv_blocks = 0, ret = 0;
	struct ext4_sb_info *sbi = EXT4_SB(mapping->host->i_sb);
	struct blk_plug plug;
	bool give_up_on_write = false;

	trace_ext4_writepages(inode, wbc);

	/*
	 * No pages to write? This is mainly a kludge to avoid starting
	 * a transaction for special inodes like journal inode on last iput()
	 * because that could violate lock ordering on umount
	 */
	if (!mapping->nrpages || !mapping_tagged(mapping, PAGECACHE_TAG_DIRTY))
		goto out_writepages;

	/*
	 * If the filesystem has aborted, it is read-only, so return
	 * right away instead of dumping stack traces later on that
	 * will obscure the real source of the problem.  We test
	 * fs shutdown state instead of sb->s_flag's SB_RDONLY because
	 * the latter could be true if the filesystem is mounted
	 * read-only, and in that case, ext4_writepages should
	 * *never* be called, so if that ever happens, we would want
	 * the stack trace.
	 */
	ret = ext4_emergency_state(mapping->host->i_sb);
	if (unlikely(ret))
		goto out_writepages;

	/*
	 * If we have inline data and arrive here, it means that
	 * we will soon create the block for the 1st page, so
	 * we'd better clear the inline data here.
	 */
	if (ext4_has_inline_data(inode)) {
		/* Just inode will be modified... */
		handle = ext4_journal_start(inode, EXT4_HT_INODE, 1);
		if (IS_ERR(handle)) {
			ret = PTR_ERR(handle);
			goto out_writepages;
		}
		BUG_ON(ext4_test_inode_state(inode,
				EXT4_STATE_MAY_INLINE_DATA));
		ext4_destroy_inline_data(handle, inode);
		ext4_journal_stop(handle);
	}

	/*
	 * data=journal mode does not do delalloc so we just need to writeout /
	 * journal already mapped buffers. On the other hand we need to commit
	 * transaction to make data stable. We expect all the data to be
	 * already in the journal (the only exception are DMA pinned pages
	 * dirtied behind our back) so we commit transaction here and run the
	 * writeback loop to checkpoint them. The checkpointing is not actually
	 * necessary to make data persistent *but* quite a few places (extent
	 * shifting operations, fsverity, ...) depend on being able to drop
	 * pagecache pages after calling filemap_write_and_wait() and for that
	 * checkpointing needs to happen.
	 */
	if (ext4_should_journal_data(inode)) {
		mpd->can_map = 0;
		if (wbc->sync_mode == WB_SYNC_ALL)
			ext4_fc_commit(sbi->s_journal,
				       EXT4_I(inode)->i_datasync_tid);
	}
	mpd->journalled_more_data = 0;

	if (ext4_should_dioread_nolock(inode)) {
		int bpf = ext4_journal_blocks_per_folio(inode);
		/*
		 * We may need to convert up to one extent per block in
		 * the folio and we may dirty the inode.
		 */
		rsv_blocks = 1 + ext4_ext_index_trans_blocks(inode, bpf);
	}

	if (wbc->range_start == 0 && wbc->range_end == LLONG_MAX)
		range_whole = 1;

	if (wbc->range_cyclic) {
		writeback_index = mapping->writeback_index;
		if (writeback_index)
			cycled = 0;
		mpd->start_pos = writeback_index << PAGE_SHIFT;
		mpd->end_pos = LLONG_MAX;
	} else {
		mpd->start_pos = wbc->range_start;
		mpd->end_pos = wbc->range_end;
	}

	ext4_io_submit_init(&mpd->io_submit, wbc);
retry:
	if (wbc->sync_mode == WB_SYNC_ALL || wbc->tagged_writepages)
		tag_pages_for_writeback(mapping, mpd->start_pos >> PAGE_SHIFT,
					mpd->end_pos >> PAGE_SHIFT);
	blk_start_plug(&plug);

	/*
	 * First writeback pages that don't need mapping - we can avoid
	 * starting a transaction unnecessarily and also avoid being blocked
	 * in the block layer on device congestion while having transaction
	 * started.
	 */
	mpd->do_map = 0;
	mpd->scanned_until_end = 0;
	mpd->io_submit.io_end = ext4_init_io_end(inode, GFP_KERNEL);
	if (!mpd->io_submit.io_end) {
		ret = -ENOMEM;
		goto unplug;
	}
	ret = mpage_prepare_extent_to_map(mpd);
	/* Unlock pages we didn't use */
	mpage_release_unused_pages(mpd, false);
	/* Submit prepared bio */
	ext4_io_submit(&mpd->io_submit);
	ext4_put_io_end_defer(mpd->io_submit.io_end);
	mpd->io_submit.io_end = NULL;
	if (ret < 0)
		goto unplug;

	while (!mpd->scanned_until_end && wbc->nr_to_write > 0) {
		/* For each extent of pages we use new io_end */
		mpd->io_submit.io_end = ext4_init_io_end(inode, GFP_KERNEL);
		if (!mpd->io_submit.io_end) {
			ret = -ENOMEM;
			break;
		}

		WARN_ON_ONCE(!mpd->can_map);
		/*
		 * We have two constraints: We find one extent to map and we
		 * must always write out whole page (makes a difference when
		 * blocksize < pagesize) so that we don't block on IO when we
		 * try to write out the rest of the page. Journalled mode is
		 * not supported by delalloc.
		 */
		BUG_ON(ext4_should_journal_data(inode));
		/*
		 * Calculate the number of credits needed to reserve for one
		 * extent of up to MAX_WRITEPAGES_EXTENT_LEN blocks. It will
		 * attempt to extend the transaction or start a new iteration
		 * if the reserved credits are insufficient.
		 */
		needed_blocks = ext4_chunk_trans_blocks(inode,
						MAX_WRITEPAGES_EXTENT_LEN);
		/* start a new transaction */
		handle = ext4_journal_start_with_reserve(inode,
				EXT4_HT_WRITE_PAGE, needed_blocks, rsv_blocks);
		if (IS_ERR(handle)) {
			ret = PTR_ERR(handle);
			ext4_msg(inode->i_sb, KERN_CRIT, "%s: jbd2_start: "
			       "%ld pages, ino %lu; err %d", __func__,
				wbc->nr_to_write, inode->i_ino, ret);
			/* Release allocated io_end */
			ext4_put_io_end(mpd->io_submit.io_end);
			mpd->io_submit.io_end = NULL;
			break;
		}
		mpd->do_map = 1;

		trace_ext4_da_write_folios_start(inode, mpd->start_pos,
				mpd->next_pos, wbc);
		ret = mpage_prepare_extent_to_map(mpd);
		if (!ret && mpd->map.m_len)
			ret = mpage_map_and_submit_extent(handle, mpd,
					&give_up_on_write);
		/*
		 * Caution: If the handle is synchronous,
		 * ext4_journal_stop() can wait for transaction commit
		 * to finish which may depend on writeback of pages to
		 * complete or on page lock to be released.  In that
		 * case, we have to wait until after we have
		 * submitted all the IO, released page locks we hold,
		 * and dropped io_end reference (for extent conversion
		 * to be able to complete) before stopping the handle.
		 */
		if (!ext4_handle_valid(handle) || handle->h_sync == 0) {
			ext4_journal_stop(handle);
			handle = NULL;
			mpd->do_map = 0;
		}
		/* Unlock pages we didn't use */
		mpage_release_unused_pages(mpd, give_up_on_write);
		/* Submit prepared bio */
		ext4_io_submit(&mpd->io_submit);

		/*
		 * Drop our io_end reference we got from init. We have
		 * to be careful and use deferred io_end finishing if
		 * we are still holding the transaction as we can
		 * release the last reference to io_end which may end
		 * up doing unwritten extent conversion.
		 */
		if (handle) {
			ext4_put_io_end_defer(mpd->io_submit.io_end);
			ext4_journal_stop(handle);
		} else
			ext4_put_io_end(mpd->io_submit.io_end);
		mpd->io_submit.io_end = NULL;
		trace_ext4_da_write_folios_end(inode, mpd->start_pos,
				mpd->next_pos, wbc, ret);

		if (ret == -ENOSPC && sbi->s_journal) {
			/*
			 * Commit the transaction which would
			 * free blocks released in the transaction
			 * and try again
			 */
			jbd2_journal_force_commit_nested(sbi->s_journal);
			ret = 0;
			continue;
		}
		if (ret == -EAGAIN)
			ret = 0;
		/* Fatal error - ENOMEM, EIO... */
		if (ret)
			break;
	}
unplug:
	blk_finish_plug(&plug);
	if (!ret && !cycled && wbc->nr_to_write > 0) {
		cycled = 1;
		mpd->end_pos = (writeback_index << PAGE_SHIFT) - 1;
		mpd->start_pos = 0;
		goto retry;
	}

	/* Update index */
	if (wbc->range_cyclic || (range_whole && wbc->nr_to_write > 0))
		/*
		 * Set the writeback_index so that range_cyclic
		 * mode will write it back later
		 */
		mapping->writeback_index = mpd->start_pos >> PAGE_SHIFT;

out_writepages:
	trace_ext4_writepages_result(inode, wbc, ret,
				     nr_to_write - wbc->nr_to_write);
	return ret;
}

static int ext4_writepages(struct address_space *mapping,
			   struct writeback_control *wbc)
{
	struct super_block *sb = mapping->host->i_sb;
	struct mpage_da_data mpd = {
		.inode = mapping->host,
		.wbc = wbc,
		.can_map = 1,
	};
	int ret;
	int alloc_ctx;

	ret = ext4_emergency_state(sb);
	if (unlikely(ret))
		return ret;

	alloc_ctx = ext4_writepages_down_read(sb);
	ret = ext4_do_writepages(&mpd);
	/*
	 * For data=journal writeback we could have come across pages marked
	 * for delayed dirtying (PageChecked) which were just added to the
	 * running transaction. Try once more to get them to stable storage.
	 */
	if (!ret && mpd.journalled_more_data)
		ret = ext4_do_writepages(&mpd);
	ext4_writepages_up_read(sb, alloc_ctx);

	return ret;
}

int ext4_normal_submit_inode_data_buffers(struct jbd2_inode *jinode)
{
	struct writeback_control wbc = {
		.sync_mode = WB_SYNC_ALL,
		.nr_to_write = LONG_MAX,
		.range_start = jinode->i_dirty_start,
		.range_end = jinode->i_dirty_end,
	};
	struct mpage_da_data mpd = {
		.inode = jinode->i_vfs_inode,
		.wbc = &wbc,
		.can_map = 0,
	};
	return ext4_do_writepages(&mpd);
}

static int ext4_dax_writepages(struct address_space *mapping,
			       struct writeback_control *wbc)
{
	int ret;
	long nr_to_write = wbc->nr_to_write;
	struct inode *inode = mapping->host;
	int alloc_ctx;

	ret = ext4_emergency_state(inode->i_sb);
	if (unlikely(ret))
		return ret;

	alloc_ctx = ext4_writepages_down_read(inode->i_sb);
	trace_ext4_writepages(inode, wbc);

	ret = dax_writeback_mapping_range(mapping,
					  EXT4_SB(inode->i_sb)->s_daxdev, wbc);
	trace_ext4_writepages_result(inode, wbc, ret,
				     nr_to_write - wbc->nr_to_write);
	ext4_writepages_up_read(inode->i_sb, alloc_ctx);
	return ret;
}

static int ext4_nonda_switch(struct super_block *sb)
{
	s64 free_clusters, dirty_clusters;
	struct ext4_sb_info *sbi = EXT4_SB(sb);

	/*
	 * switch to non delalloc mode if we are running low
	 * on free block. The free block accounting via percpu
	 * counters can get slightly wrong with percpu_counter_batch getting
	 * accumulated on each CPU without updating global counters
	 * Delalloc need an accurate free block accounting. So switch
	 * to non delalloc when we are near to error range.
	 */
	free_clusters =
		percpu_counter_read_positive(&sbi->s_freeclusters_counter);
	dirty_clusters =
		percpu_counter_read_positive(&sbi->s_dirtyclusters_counter);
	/*
	 * Start pushing delalloc when 1/2 of free blocks are dirty.
	 */
	if (dirty_clusters && (free_clusters < 2 * dirty_clusters))
		try_to_writeback_inodes_sb(sb, WB_REASON_FS_FREE_SPACE);

	if (2 * free_clusters < 3 * dirty_clusters ||
	    free_clusters < (dirty_clusters + EXT4_FREECLUSTERS_WATERMARK)) {
		/*
		 * free block count is less than 150% of dirty blocks
		 * or free blocks is less than watermark
		 */
		return 1;
	}
	return 0;
}

static int ext4_da_write_begin(const struct kiocb *iocb,
			       struct address_space *mapping,
			       loff_t pos, unsigned len,
			       struct folio **foliop, void **fsdata)
{
	int ret, retries = 0;
	struct folio *folio;
	pgoff_t index;
	struct inode *inode = mapping->host;

	ret = ext4_emergency_state(inode->i_sb);
	if (unlikely(ret))
		return ret;

	index = pos >> PAGE_SHIFT;

	if (ext4_nonda_switch(inode->i_sb) || ext4_verity_in_progress(inode)) {
		*fsdata = (void *)FALL_BACK_TO_NONDELALLOC;
		return ext4_write_begin(iocb, mapping, pos,
					len, foliop, fsdata);
	}
	*fsdata = (void *)0;
	trace_ext4_da_write_begin(inode, pos, len);

	if (ext4_test_inode_state(inode, EXT4_STATE_MAY_INLINE_DATA)) {
		ret = ext4_generic_write_inline_data(mapping, inode, pos, len,
						     foliop, fsdata, true);
		if (ret < 0)
			return ret;
		if (ret == 1)
			return 0;
	}

retry:
	folio = write_begin_get_folio(iocb, mapping, index, len);
	if (IS_ERR(folio))
		return PTR_ERR(folio);

	if (len > folio_next_pos(folio) - pos)
		len = folio_next_pos(folio) - pos;

	ret = ext4_block_write_begin(NULL, folio, pos, len,
				     ext4_da_get_block_prep);
	if (ret < 0) {
		folio_unlock(folio);
		folio_put(folio);
		/*
		 * ext4_block_write_begin may have instantiated a few blocks
		 * outside i_size.  Trim these off again. Don't need
		 * i_size_read because we hold inode lock.
		 */
		if (pos + len > inode->i_size)
			ext4_truncate_failed_write(inode);

		if (ret == -ENOSPC &&
		    ext4_should_retry_alloc(inode->i_sb, &retries))
			goto retry;
		return ret;
	}

	*foliop = folio;
	return ret;
}

/*
 * Check if we should update i_disksize
 * when write to the end of file but not require block allocation
 */
static int ext4_da_should_update_i_disksize(struct folio *folio,
					    unsigned long offset)
{
	struct buffer_head *bh;
	struct inode *inode = folio->mapping->host;
	unsigned int idx;
	int i;

	bh = folio_buffers(folio);
	idx = offset >> inode->i_blkbits;

	for (i = 0; i < idx; i++)
		bh = bh->b_this_page;

	if (!buffer_mapped(bh) || (buffer_delay(bh)) || buffer_unwritten(bh))
		return 0;
	return 1;
}

static int ext4_da_do_write_end(struct address_space *mapping,
			loff_t pos, unsigned len, unsigned copied,
			struct folio *folio)
{
	struct inode *inode = mapping->host;
	loff_t old_size = inode->i_size;
	bool disksize_changed = false;
	loff_t new_i_size, zero_len = 0;
	handle_t *handle;

	if (unlikely(!folio_buffers(folio))) {
		folio_unlock(folio);
		folio_put(folio);
		return -EIO;
	}
	/*
	 * block_write_end() will mark the inode as dirty with I_DIRTY_PAGES
	 * flag, which all that's needed to trigger page writeback.
	 */
	copied = block_write_end(pos, len, copied, folio);
	new_i_size = pos + copied;

	/*
	 * It's important to update i_size while still holding folio lock,
	 * because folio writeout could otherwise come in and zero beyond
	 * i_size.
	 *
	 * Since we are holding inode lock, we are sure i_disksize <=
	 * i_size. We also know that if i_disksize < i_size, there are
	 * delalloc writes pending in the range up to i_size. If the end of
	 * the current write is <= i_size, there's no need to touch
	 * i_disksize since writeback will push i_disksize up to i_size
	 * eventually. If the end of the current write is > i_size and
	 * inside an allocated block which ext4_da_should_update_i_disksize()
	 * checked, we need to update i_disksize here as certain
	 * ext4_writepages() paths not allocating blocks and update i_disksize.
	 */
	if (new_i_size > inode->i_size) {
		unsigned long end;

		i_size_write(inode, new_i_size);
		end = offset_in_folio(folio, new_i_size - 1);
		if (copied && ext4_da_should_update_i_disksize(folio, end)) {
			ext4_update_i_disksize(inode, new_i_size);
			disksize_changed = true;
		}
	}

	folio_unlock(folio);
	folio_put(folio);

	if (pos > old_size) {
		pagecache_isize_extended(inode, old_size, pos);
		zero_len = pos - old_size;
	}

	if (!disksize_changed && !zero_len)
		return copied;

	handle = ext4_journal_start(inode, EXT4_HT_INODE, 2);
	if (IS_ERR(handle))
		return PTR_ERR(handle);
	if (zero_len)
		ext4_zero_partial_blocks(handle, inode, old_size, zero_len);
	ext4_mark_inode_dirty(handle, inode);
	ext4_journal_stop(handle);

	return copied;
}

static int ext4_da_write_end(const struct kiocb *iocb,
			     struct address_space *mapping,
			     loff_t pos, unsigned len, unsigned copied,
			     struct folio *folio, void *fsdata)
{
	struct inode *inode = mapping->host;
	int write_mode = (int)(unsigned long)fsdata;

	if (write_mode == FALL_BACK_TO_NONDELALLOC)
		return ext4_write_end(iocb, mapping, pos,
				      len, copied, folio, fsdata);

	trace_ext4_da_write_end(inode, pos, len, copied);

	if (write_mode != CONVERT_INLINE_DATA &&
	    ext4_test_inode_state(inode, EXT4_STATE_MAY_INLINE_DATA) &&
	    ext4_has_inline_data(inode))
		return ext4_write_inline_data_end(inode, pos, len, copied,
						  folio);

	if (unlikely(copied < len) && !folio_test_uptodate(folio))
		copied = 0;

	return ext4_da_do_write_end(mapping, pos, len, copied, folio);
}

/*
 * Force all delayed allocation blocks to be allocated for a given inode.
 */
int ext4_alloc_da_blocks(struct inode *inode)
{
	trace_ext4_alloc_da_blocks(inode);

	if (!EXT4_I(inode)->i_reserved_data_blocks)
		return 0;

	/*
	 * We do something simple for now.  The filemap_flush() will
	 * also start triggering a write of the data blocks, which is
	 * not strictly speaking necessary.  However, to do otherwise
	 * would require replicating code paths in:
	 *
	 * ext4_writepages() ->
	 *    write_cache_pages() ---> (via passed in callback function)
	 *        __mpage_da_writepage() -->
	 *           mpage_add_bh_to_extent()
	 *           mpage_da_map_blocks()
	 *
	 * The problem is that write_cache_pages(), located in
	 * mm/page-writeback.c, marks pages clean in preparation for
	 * doing I/O, which is not desirable if we're not planning on
	 * doing I/O at all.
	 *
	 * We could call write_cache_pages(), and then redirty all of
	 * the pages by calling redirty_page_for_writepage() but that
	 * would be ugly in the extreme.  So instead we would need to
	 * replicate parts of the code in the above functions,
	 * simplifying them because we wouldn't actually intend to
	 * write out the pages, but rather only collect contiguous
	 * logical block extents, call the multi-block allocator, and
	 * then update the buffer heads with the block allocations.
	 *
	 * For now, though, we'll cheat by calling filemap_flush(),
	 * which will map the blocks, and start the I/O, but not
	 * actually wait for the I/O to complete.
	 */
	return filemap_flush(inode->i_mapping);
}

/*
 * bmap() is special.  It gets used by applications such as lilo and by
 * the swapper to find the on-disk block of a specific piece of data.
 *
 * Naturally, this is dangerous if the block concerned is still in the
 * journal.  If somebody makes a swapfile on an ext4 data-journaling
 * filesystem and enables swap, then they may get a nasty shock when the
 * data getting swapped to that swapfile suddenly gets overwritten by
 * the original zero's written out previously to the journal and
 * awaiting writeback in the kernel's buffer cache.
 *
 * So, if we see any bmap calls here on a modified, data-journaled file,
 * take extra steps to flush any blocks which might be in the cache.
 */
static sector_t ext4_bmap(struct address_space *mapping, sector_t block)
{
	struct inode *inode = mapping->host;
	sector_t ret = 0;

	inode_lock_shared(inode);
	/*
	 * We can get here for an inline file via the FIBMAP ioctl
	 */
	if (ext4_has_inline_data(inode
