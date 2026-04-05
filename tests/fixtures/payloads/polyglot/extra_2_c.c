// SPDX-License-Identifier: GPL-2.0-only
/*
 *  linux/mm/memory.c
 *
 *  Copyright (C) 1991, 1992, 1993, 1994  Linus Torvalds
 */

/*
 * demand-loading started 01.12.91 - seems it is high on the list of
 * things wanted, and it should be easy to implement. - Linus
 */

/*
 * Ok, demand-loading was easy, shared pages a little bit tricker. Shared
 * pages started 02.12.91, seems to work. - Linus.
 *
 * Tested sharing by executing about 30 /bin/sh: under the old kernel it
 * would have taken more than the 6M I have free, but it worked well as
 * far as I could see.
 *
 * Also corrected some "invalidate()"s - I wasn't doing enough of them.
 */

/*
 * Real VM (paging to/from disk) started 18.12.91. Much more work and
 * thought has to go into this. Oh, well..
 * 19.12.91  -  works, somewhat. Sometimes I get faults, don't know why.
 *		Found it. Everything seems to work now.
 * 20.12.91  -  Ok, making the swap-device changeable like the root.
 */

/*
 * 05.04.94  -  Multi-page memory management added for v1.1.
 *              Idea by Alex Bligh (alex@cconcepts.co.uk)
 *
 * 16.07.99  -  Support of BIGMEM added by Gerhard Wichert, Siemens AG
 *		(Gerhard.Wichert@pdb.siemens.de)
 *
 * Aug/Sep 2004 Changed to four level page tables (Andi Kleen)
 */

#include <linux/kernel_stat.h>
#include <linux/mm.h>
#include <linux/mm_inline.h>
#include <linux/sched/mm.h>
#include <linux/sched/numa_balancing.h>
#include <linux/sched/task.h>
#include <linux/hugetlb.h>
#include <linux/mman.h>
#include <linux/swap.h>
#include <linux/highmem.h>
#include <linux/pagemap.h>
#include <linux/memremap.h>
#include <linux/kmsan.h>
#include <linux/ksm.h>
#include <linux/rmap.h>
#include <linux/export.h>
#include <linux/delayacct.h>
#include <linux/init.h>
#include <linux/writeback.h>
#include <linux/memcontrol.h>
#include <linux/mmu_notifier.h>
#include <linux/leafops.h>
#include <linux/elf.h>
#include <linux/gfp.h>
#include <linux/migrate.h>
#include <linux/string.h>
#include <linux/shmem_fs.h>
#include <linux/memory-tiers.h>
#include <linux/debugfs.h>
#include <linux/userfaultfd_k.h>
#include <linux/dax.h>
#include <linux/oom.h>
#include <linux/numa.h>
#include <linux/perf_event.h>
#include <linux/ptrace.h>
#include <linux/vmalloc.h>
#include <linux/sched/sysctl.h>
#include <linux/pgalloc.h>
#include <linux/uaccess.h>

#include <trace/events/kmem.h>

#include <asm/io.h>
#include <asm/mmu_context.h>
#include <asm/tlb.h>
#include <asm/tlbflush.h>

#include "pgalloc-track.h"
#include "internal.h"
#include "swap.h"

#if defined(LAST_CPUPID_NOT_IN_PAGE_FLAGS) && !defined(CONFIG_COMPILE_TEST)
#warning Unfortunate NUMA and NUMA Balancing config, growing page-frame for last_cpupid.
#endif

static vm_fault_t do_fault(struct vm_fault *vmf);
static vm_fault_t do_anonymous_page(struct vm_fault *vmf);
static bool vmf_pte_changed(struct vm_fault *vmf);

/*
 * Return true if the original pte was a uffd-wp pte marker (so the pte was
 * wr-protected).
 */
static __always_inline bool vmf_orig_pte_uffd_wp(struct vm_fault *vmf)
{
	if (!userfaultfd_wp(vmf->vma))
		return false;
	if (!(vmf->flags & FAULT_FLAG_ORIG_PTE_VALID))
		return false;

	return pte_is_uffd_wp_marker(vmf->orig_pte);
}

/*
 * Randomize the address space (stacks, mmaps, brk, etc.).
 *
 * ( When CONFIG_COMPAT_BRK=y we exclude brk from randomization,
 *   as ancient (libc5 based) binaries can segfault. )
 */
int randomize_va_space __read_mostly =
#ifdef CONFIG_COMPAT_BRK
					1;
#else
					2;
#endif

static const struct ctl_table mmu_sysctl_table[] = {
	{
		.procname	= "randomize_va_space",
		.data		= &randomize_va_space,
		.maxlen		= sizeof(int),
		.mode		= 0644,
		.proc_handler	= proc_dointvec,
	},
};

static int __init init_mm_sysctl(void)
{
	register_sysctl_init("kernel", mmu_sysctl_table);
	return 0;
}

subsys_initcall(init_mm_sysctl);

#ifndef arch_wants_old_prefaulted_pte
static inline bool arch_wants_old_prefaulted_pte(void)
{
	/*
	 * Transitioning a PTE from 'old' to 'young' can be expensive on
	 * some architectures, even if it's performed in hardware. By
	 * default, "false" means prefaulted entries will be 'young'.
	 */
	return false;
}
#endif

static int __init disable_randmaps(char *s)
{
	randomize_va_space = 0;
	return 1;
}
__setup("norandmaps", disable_randmaps);

unsigned long zero_pfn __read_mostly;
EXPORT_SYMBOL(zero_pfn);

unsigned long highest_memmap_pfn __read_mostly;

/*
 * CONFIG_MMU architectures set up ZERO_PAGE in their paging_init()
 */
static int __init init_zero_pfn(void)
{
	zero_pfn = page_to_pfn(ZERO_PAGE(0));
	return 0;
}
early_initcall(init_zero_pfn);

void mm_trace_rss_stat(struct mm_struct *mm, int member)
{
	trace_rss_stat(mm, member);
}

/*
 * Note: this doesn't free the actual pages themselves. That
 * has been handled earlier when unmapping all the memory regions.
 */
static void free_pte_range(struct mmu_gather *tlb, pmd_t *pmd,
			   unsigned long addr)
{
	pgtable_t token = pmd_pgtable(*pmd);
	pmd_clear(pmd);
	pte_free_tlb(tlb, token, addr);
	mm_dec_nr_ptes(tlb->mm);
}

static inline void free_pmd_range(struct mmu_gather *tlb, pud_t *pud,
				unsigned long addr, unsigned long end,
				unsigned long floor, unsigned long ceiling)
{
	pmd_t *pmd;
	unsigned long next;
	unsigned long start;

	start = addr;
	pmd = pmd_offset(pud, addr);
	do {
		next = pmd_addr_end(addr, end);
		if (pmd_none_or_clear_bad(pmd))
			continue;
		free_pte_range(tlb, pmd, addr);
	} while (pmd++, addr = next, addr != end);

	start &= PUD_MASK;
	if (start < floor)
		return;
	if (ceiling) {
		ceiling &= PUD_MASK;
		if (!ceiling)
			return;
	}
	if (end - 1 > ceiling - 1)
		return;

	pmd = pmd_offset(pud, start);
	pud_clear(pud);
	pmd_free_tlb(tlb, pmd, start);
	mm_dec_nr_pmds(tlb->mm);
}

static inline void free_pud_range(struct mmu_gather *tlb, p4d_t *p4d,
				unsigned long addr, unsigned long end,
				unsigned long floor, unsigned long ceiling)
{
	pud_t *pud;
	unsigned long next;
	unsigned long start;

	start = addr;
	pud = pud_offset(p4d, addr);
	do {
		next = pud_addr_end(addr, end);
		if (pud_none_or_clear_bad(pud))
			continue;
		free_pmd_range(tlb, pud, addr, next, floor, ceiling);
	} while (pud++, addr = next, addr != end);

	start &= P4D_MASK;
	if (start < floor)
		return;
	if (ceiling) {
		ceiling &= P4D_MASK;
		if (!ceiling)
			return;
	}
	if (end - 1 > ceiling - 1)
		return;

	pud = pud_offset(p4d, start);
	p4d_clear(p4d);
	pud_free_tlb(tlb, pud, start);
	mm_dec_nr_puds(tlb->mm);
}

static inline void free_p4d_range(struct mmu_gather *tlb, pgd_t *pgd,
				unsigned long addr, unsigned long end,
				unsigned long floor, unsigned long ceiling)
{
	p4d_t *p4d;
	unsigned long next;
	unsigned long start;

	start = addr;
	p4d = p4d_offset(pgd, addr);
	do {
		next = p4d_addr_end(addr, end);
		if (p4d_none_or_clear_bad(p4d))
			continue;
		free_pud_range(tlb, p4d, addr, next, floor, ceiling);
	} while (p4d++, addr = next, addr != end);

	start &= PGDIR_MASK;
	if (start < floor)
		return;
	if (ceiling) {
		ceiling &= PGDIR_MASK;
		if (!ceiling)
			return;
	}
	if (end - 1 > ceiling - 1)
		return;

	p4d = p4d_offset(pgd, start);
	pgd_clear(pgd);
	p4d_free_tlb(tlb, p4d, start);
}

/**
 * free_pgd_range - Unmap and free page tables in the range
 * @tlb: the mmu_gather containing pending TLB flush info
 * @addr: virtual address start
 * @end: virtual address end
 * @floor: lowest address boundary
 * @ceiling: highest address boundary
 *
 * This function tears down all user-level page tables in the
 * specified virtual address range [@addr..@end). It is part of
 * the memory unmap flow.
 */
void free_pgd_range(struct mmu_gather *tlb,
			unsigned long addr, unsigned long end,
			unsigned long floor, unsigned long ceiling)
{
	pgd_t *pgd;
	unsigned long next;

	/*
	 * The next few lines have given us lots of grief...
	 *
	 * Why are we testing PMD* at this top level?  Because often
	 * there will be no work to do at all, and we'd prefer not to
	 * go all the way down to the bottom just to discover that.
	 *
	 * Why all these "- 1"s?  Because 0 represents both the bottom
	 * of the address space and the top of it (using -1 for the
	 * top wouldn't help much: the masks would do the wrong thing).
	 * The rule is that addr 0 and floor 0 refer to the bottom of
	 * the address space, but end 0 and ceiling 0 refer to the top
	 * Comparisons need to use "end - 1" and "ceiling - 1" (though
	 * that end 0 case should be mythical).
	 *
	 * Wherever addr is brought up or ceiling brought down, we must
	 * be careful to reject "the opposite 0" before it confuses the
	 * subsequent tests.  But what about where end is brought down
	 * by PMD_SIZE below? no, end can't go down to 0 there.
	 *
	 * Whereas we round start (addr) and ceiling down, by different
	 * masks at different levels, in order to test whether a table
	 * now has no other vmas using it, so can be freed, we don't
	 * bother to round floor or end up - the tests don't need that.
	 */

	addr &= PMD_MASK;
	if (addr < floor) {
		addr += PMD_SIZE;
		if (!addr)
			return;
	}
	if (ceiling) {
		ceiling &= PMD_MASK;
		if (!ceiling)
			return;
	}
	if (end - 1 > ceiling - 1)
		end -= PMD_SIZE;
	if (addr > end - 1)
		return;
	/*
	 * We add page table cache pages with PAGE_SIZE,
	 * (see pte_free_tlb()), flush the tlb if we need
	 */
	tlb_change_page_size(tlb, PAGE_SIZE);
	pgd = pgd_offset(tlb->mm, addr);
	do {
		next = pgd_addr_end(addr, end);
		if (pgd_none_or_clear_bad(pgd))
			continue;
		free_p4d_range(tlb, pgd, addr, next, floor, ceiling);
	} while (pgd++, addr = next, addr != end);
}

/**
 * free_pgtables() - Free a range of page tables
 * @tlb: The mmu gather
 * @unmap: The unmap_desc
 *
 * Note: pg_start and pg_end are provided to indicate the absolute range of the
 * page tables that should be removed.  This can differ from the vma mappings on
 * some archs that may have mappings that need to be removed outside the vmas.
 * Note that the prev->vm_end and next->vm_start are often used.
 *
 * The vma_end differs from the pg_end when a dup_mmap() failed and the tree has
 * unrelated data to the mm_struct being torn down.
 */
void free_pgtables(struct mmu_gather *tlb, struct unmap_desc *unmap)
{
	struct unlink_vma_file_batch vb;
	struct ma_state *mas = unmap->mas;
	struct vm_area_struct *vma = unmap->first;

	/*
	 * Note: USER_PGTABLES_CEILING may be passed as the value of pg_end and
	 * may be 0.  Underflow is expected in this case.  Otherwise the
	 * pagetable end is exclusive.  vma_end is exclusive.  The last vma
	 * address should never be larger than the pagetable end.
	 */
	WARN_ON_ONCE(unmap->vma_end - 1 > unmap->pg_end - 1);

	tlb_free_vmas(tlb);

	do {
		unsigned long addr = vma->vm_start;
		struct vm_area_struct *next;

		next = mas_find(mas, unmap->tree_end - 1);

		/*
		 * Hide vma from rmap and truncate_pagecache before freeing
		 * pgtables
		 */
		if (unmap->mm_wr_locked)
			vma_start_write(vma);
		unlink_anon_vmas(vma);

		unlink_file_vma_batch_init(&vb);
		unlink_file_vma_batch_add(&vb, vma);

		/*
		 * Optimization: gather nearby vmas into one call down
		 */
		while (next && next->vm_start <= vma->vm_end + PMD_SIZE) {
			vma = next;
			next = mas_find(mas, unmap->tree_end - 1);
			if (unmap->mm_wr_locked)
				vma_start_write(vma);
			unlink_anon_vmas(vma);
			unlink_file_vma_batch_add(&vb, vma);
		}
		unlink_file_vma_batch_final(&vb);

		free_pgd_range(tlb, addr, vma->vm_end, unmap->pg_start,
			       next ? next->vm_start : unmap->pg_end);
		vma = next;
	} while (vma);
}

void pmd_install(struct mm_struct *mm, pmd_t *pmd, pgtable_t *pte)
{
	spinlock_t *ptl = pmd_lock(mm, pmd);

	if (likely(pmd_none(*pmd))) {	/* Has another populated it ? */
		mm_inc_nr_ptes(mm);
		/*
		 * Ensure all pte setup (eg. pte page lock and page clearing) are
		 * visible before the pte is made visible to other CPUs by being
		 * put into page tables.
		 *
		 * The other side of the story is the pointer chasing in the page
		 * table walking code (when walking the page table without locking;
		 * ie. most of the time). Fortunately, these data accesses consist
		 * of a chain of data-dependent loads, meaning most CPUs (alpha
		 * being the notable exception) will already guarantee loads are
		 * seen in-order. See the alpha page table accessors for the
		 * smp_rmb() barriers in page table walking code.
		 */
		smp_wmb(); /* Could be smp_wmb__xxx(before|after)_spin_lock */
		pmd_populate(mm, pmd, *pte);
		*pte = NULL;
	}
	spin_unlock(ptl);
}

int __pte_alloc(struct mm_struct *mm, pmd_t *pmd)
{
	pgtable_t new = pte_alloc_one(mm);
	if (!new)
		return -ENOMEM;

	pmd_install(mm, pmd, &new);
	if (new)
		pte_free(mm, new);
	return 0;
}

int __pte_alloc_kernel(pmd_t *pmd)
{
	pte_t *new = pte_alloc_one_kernel(&init_mm);
	if (!new)
		return -ENOMEM;

	spin_lock(&init_mm.page_table_lock);
	if (likely(pmd_none(*pmd))) {	/* Has another populated it ? */
		smp_wmb(); /* See comment in pmd_install() */
		pmd_populate_kernel(&init_mm, pmd, new);
		new = NULL;
	}
	spin_unlock(&init_mm.page_table_lock);
	if (new)
		pte_free_kernel(&init_mm, new);
	return 0;
}

static inline void init_rss_vec(int *rss)
{
	memset(rss, 0, sizeof(int) * NR_MM_COUNTERS);
}

static inline void add_mm_rss_vec(struct mm_struct *mm, int *rss)
{
	int i;

	for (i = 0; i < NR_MM_COUNTERS; i++)
		if (rss[i])
			add_mm_counter(mm, i, rss[i]);
}

static bool is_bad_page_map_ratelimited(void)
{
	static unsigned long resume;
	static unsigned long nr_shown;
	static unsigned long nr_unshown;

	/*
	 * Allow a burst of 60 reports, then keep quiet for that minute;
	 * or allow a steady drip of one report per second.
	 */
	if (nr_shown == 60) {
		if (time_before(jiffies, resume)) {
			nr_unshown++;
			return true;
		}
		if (nr_unshown) {
			pr_alert("BUG: Bad page map: %lu messages suppressed\n",
				 nr_unshown);
			nr_unshown = 0;
		}
		nr_shown = 0;
	}
	if (nr_shown++ == 0)
		resume = jiffies + 60 * HZ;
	return false;
}

static void __print_bad_page_map_pgtable(struct mm_struct *mm, unsigned long addr)
{
	unsigned long long pgdv, p4dv, pudv, pmdv;
	p4d_t p4d, *p4dp;
	pud_t pud, *pudp;
	pmd_t pmd, *pmdp;
	pgd_t *pgdp;

	/*
	 * Although this looks like a fully lockless pgtable walk, it is not:
	 * see locking requirements for print_bad_page_map().
	 */
	pgdp = pgd_offset(mm, addr);
	pgdv = pgd_val(*pgdp);

	if (!pgd_present(*pgdp) || pgd_leaf(*pgdp)) {
		pr_alert("pgd:%08llx\n", pgdv);
		return;
	}

	p4dp = p4d_offset(pgdp, addr);
	p4d = p4dp_get(p4dp);
	p4dv = p4d_val(p4d);

	if (!p4d_present(p4d) || p4d_leaf(p4d)) {
		pr_alert("pgd:%08llx p4d:%08llx\n", pgdv, p4dv);
		return;
	}

	pudp = pud_offset(p4dp, addr);
	pud = pudp_get(pudp);
	pudv = pud_val(pud);

	if (!pud_present(pud) || pud_leaf(pud)) {
		pr_alert("pgd:%08llx p4d:%08llx pud:%08llx\n", pgdv, p4dv, pudv);
		return;
	}

	pmdp = pmd_offset(pudp, addr);
	pmd = pmdp_get(pmdp);
	pmdv = pmd_val(pmd);

	/*
	 * Dumping the PTE would be nice, but it's tricky with CONFIG_HIGHPTE,
	 * because the table should already be mapped by the caller and
	 * doing another map would be bad. print_bad_page_map() should
	 * already take care of printing the PTE.
	 */
	pr_alert("pgd:%08llx p4d:%08llx pud:%08llx pmd:%08llx\n", pgdv,
		 p4dv, pudv, pmdv);
}

/*
 * This function is called to print an error when a bad page table entry (e.g.,
 * corrupted page table entry) is found. For example, we might have a
 * PFN-mapped pte in a region that doesn't allow it.
 *
 * The calling function must still handle the error.
 *
 * This function must be called during a proper page table walk, as it will
 * re-walk the page table to dump information: the caller MUST prevent page
 * table teardown (by holding mmap, vma or rmap lock) and MUST hold the leaf
 * page table lock.
 */
static void print_bad_page_map(struct vm_area_struct *vma,
		unsigned long addr, unsigned long long entry, struct page *page,
		enum pgtable_level level)
{
	struct address_space *mapping;
	pgoff_t index;

	if (is_bad_page_map_ratelimited())
		return;

	mapping = vma->vm_file ? vma->vm_file->f_mapping : NULL;
	index = linear_page_index(vma, addr);

	pr_alert("BUG: Bad page map in process %s  %s:%08llx", current->comm,
		 pgtable_level_to_str(level), entry);
	__print_bad_page_map_pgtable(vma->vm_mm, addr);
	if (page)
		dump_page(page, "bad page map");
	pr_alert("addr:%px vm_flags:%08lx anon_vma:%px mapping:%px index:%lx\n",
		 (void *)addr, vma->vm_flags, vma->anon_vma, mapping, index);
	pr_alert("file:%pD fault:%ps mmap:%ps mmap_prepare: %ps read_folio:%ps\n",
		 vma->vm_file,
		 vma->vm_ops ? vma->vm_ops->fault : NULL,
		 vma->vm_file ? vma->vm_file->f_op->mmap : NULL,
		 vma->vm_file ? vma->vm_file->f_op->mmap_prepare : NULL,
		 mapping ? mapping->a_ops->read_folio : NULL);
	dump_stack();
	add_taint(TAINT_BAD_PAGE, LOCKDEP_NOW_UNRELIABLE);
}
#define print_bad_pte(vma, addr, pte, page) \
	print_bad_page_map(vma, addr, pte_val(pte), page, PGTABLE_LEVEL_PTE)

/**
 * __vm_normal_page() - Get the "struct page" associated with a page table entry.
 * @vma: The VMA mapping the page table entry.
 * @addr: The address where the page table entry is mapped.
 * @pfn: The PFN stored in the page table entry.
 * @special: Whether the page table entry is marked "special".
 * @level: The page table level for error reporting purposes only.
 * @entry: The page table entry value for error reporting purposes only.
 *
 * "Special" mappings do not wish to be associated with a "struct page" (either
 * it doesn't exist, or it exists but they don't want to touch it). In this
 * case, NULL is returned here. "Normal" mappings do have a struct page and
 * are ordinarily refcounted.
 *
 * Page mappings of the shared zero folios are always considered "special", as
 * they are not ordinarily refcounted: neither the refcount nor the mapcount
 * of these folios is adjusted when mapping them into user page tables.
 * Selected page table walkers (such as GUP) can still identify mappings of the
 * shared zero folios and work with the underlying "struct page".
 *
 * There are 2 broad cases. Firstly, an architecture may define a "special"
 * page table entry bit, such as pte_special(), in which case this function is
 * trivial. Secondly, an architecture may not have a spare page table
 * entry bit, which requires a more complicated scheme, described below.
 *
 * With CONFIG_FIND_NORMAL_PAGE, we might have the "special" bit set on
 * page table entries that actually map "normal" pages: however, that page
 * cannot be looked up through the PFN stored in the page table entry, but
 * instead will be looked up through vm_ops->find_normal_page(). So far, this
 * only applies to PTEs.
 *
 * A raw VM_PFNMAP mapping (ie. one that is not COWed) is always considered a
 * special mapping (even if there are underlying and valid "struct pages").
 * COWed pages of a VM_PFNMAP are always normal.
 *
 * The way we recognize COWed pages within VM_PFNMAP mappings is through the
 * rules set up by "remap_pfn_range()": the vma will have the VM_PFNMAP bit
 * set, and the vm_pgoff will point to the first PFN mapped: thus every special
 * mapping will always honor the rule
 *
 *	pfn_of_page == vma->vm_pgoff + ((addr - vma->vm_start) >> PAGE_SHIFT)
 *
 * And for normal mappings this is false.
 *
 * This restricts such mappings to be a linear translation from virtual address
 * to pfn. To get around this restriction, we allow arbitrary mappings so long
 * as the vma is not a COW mapping; in that case, we know that all ptes are
 * special (because none can have been COWed).
 *
 *
 * In order to support COW of arbitrary special mappings, we have VM_MIXEDMAP.
 *
 * VM_MIXEDMAP mappings can likewise contain memory with or without "struct
 * page" backing, however the difference is that _all_ pages with a struct
 * page (that is, those where pfn_valid is true, except the shared zero
 * folios) are refcounted and considered normal pages by the VM.
 *
 * The disadvantage is that pages are refcounted (which can be slower and
 * simply not an option for some PFNMAP users). The advantage is that we
 * don't have to follow the strict linearity rule of PFNMAP mappings in
 * order to support COWable mappings.
 *
 * Return: Returns the "struct page" if this is a "normal" mapping. Returns
 *	   NULL if this is a "special" mapping.
 */
static inline struct page *__vm_normal_page(struct vm_area_struct *vma,
		unsigned long addr, unsigned long pfn, bool special,
		unsigned long long entry, enum pgtable_level level)
{
	if (IS_ENABLED(CONFIG_ARCH_HAS_PTE_SPECIAL)) {
		if (unlikely(special)) {
#ifdef CONFIG_FIND_NORMAL_PAGE
			if (vma->vm_ops && vma->vm_ops->find_normal_page)
				return vma->vm_ops->find_normal_page(vma, addr);
#endif /* CONFIG_FIND_NORMAL_PAGE */
			if (vma->vm_flags & (VM_PFNMAP | VM_MIXEDMAP))
				return NULL;
			if (is_zero_pfn(pfn) || is_huge_zero_pfn(pfn))
				return NULL;

			print_bad_page_map(vma, addr, entry, NULL, level);
			return NULL;
		}
		/*
		 * With CONFIG_ARCH_HAS_PTE_SPECIAL, any special page table
		 * mappings (incl. shared zero folios) are marked accordingly.
		 */
	} else {
		if (unlikely(vma->vm_flags & (VM_PFNMAP | VM_MIXEDMAP))) {
			if (vma->vm_flags & VM_MIXEDMAP) {
				/* If it has a "struct page", it's "normal". */
				if (!pfn_valid(pfn))
					return NULL;
			} else {
				unsigned long off = (addr - vma->vm_start) >> PAGE_SHIFT;

				/* Only CoW'ed anon folios are "normal". */
				if (pfn == vma->vm_pgoff + off)
					return NULL;
				if (!is_cow_mapping(vma->vm_flags))
					return NULL;
			}
		}

		if (is_zero_pfn(pfn) || is_huge_zero_pfn(pfn))
			return NULL;
	}

	if (unlikely(pfn > highest_memmap_pfn)) {
		/* Corrupted page table entry. */
		print_bad_page_map(vma, addr, entry, NULL, level);
		return NULL;
	}
	/*
	 * NOTE! We still have PageReserved() pages in the page tables.
	 * For example, VDSO mappings can cause them to exist.
	 */
	VM_WARN_ON_ONCE(is_zero_pfn(pfn) || is_huge_zero_pfn(pfn));
	return pfn_to_page(pfn);
}

/**
 * vm_normal_page() - Get the "struct page" associated with a PTE
 * @vma: The VMA mapping the @pte.
 * @addr: The address where the @pte is mapped.
 * @pte: The PTE.
 *
 * Get the "struct page" associated with a PTE. See __vm_normal_page()
 * for details on "normal" and "special" mappings.
 *
 * Return: Returns the "struct page" if this is a "normal" mapping. Returns
 *	   NULL if this is a "special" mapping.
 */
struct page *vm_normal_page(struct vm_area_struct *vma, unsigned long addr,
			    pte_t pte)
{
	return __vm_normal_page(vma, addr, pte_pfn(pte), pte_special(pte),
				pte_val(pte), PGTABLE_LEVEL_PTE);
}

/**
 * vm_normal_folio() - Get the "struct folio" associated with a PTE
 * @vma: The VMA mapping the @pte.
 * @addr: The address where the @pte is mapped.
 * @pte: The PTE.
 *
 * Get the "struct folio" associated with a PTE. See __vm_normal_page()
 * for details on "normal" and "special" mappings.
 *
 * Return: Returns the "struct folio" if this is a "normal" mapping. Returns
 *	   NULL if this is a "special" mapping.
 */
struct folio *vm_normal_folio(struct vm_area_struct *vma, unsigned long addr,
			    pte_t pte)
{
	struct page *page = vm_normal_page(vma, addr, pte);

	if (page)
		return page_folio(page);
	return NULL;
}

#ifdef CONFIG_PGTABLE_HAS_HUGE_LEAVES
/**
 * vm_normal_page_pmd() - Get the "struct page" associated with a PMD
 * @vma: The VMA mapping the @pmd.
 * @addr: The address where the @pmd is mapped.
 * @pmd: The PMD.
 *
 * Get the "struct page" associated with a PTE. See __vm_normal_page()
 * for details on "normal" and "special" mappings.
 *
 * Return: Returns the "struct page" if this is a "normal" mapping. Returns
 *	   NULL if this is a "special" mapping.
 */
struct page *vm_normal_page_pmd(struct vm_area_struct *vma, unsigned long addr,
				pmd_t pmd)
{
	return __vm_normal_page(vma, addr, pmd_pfn(pmd), pmd_special(pmd),
				pmd_val(pmd), PGTABLE_LEVEL_PMD);
}

/**
 * vm_normal_folio_pmd() - Get the "struct folio" associated with a PMD
 * @vma: The VMA mapping the @pmd.
 * @addr: The address where the @pmd is mapped.
 * @pmd: The PMD.
 *
 * Get the "struct folio" associated with a PTE. See __vm_normal_page()
 * for details on "normal" and "special" mappings.
 *
 * Return: Returns the "struct folio" if this is a "normal" mapping. Returns
 *	   NULL if this is a "special" mapping.
 */
struct folio *vm_normal_folio_pmd(struct vm_area_struct *vma,
				  unsigned long addr, pmd_t pmd)
{
	struct page *page = vm_normal_page_pmd(vma, addr, pmd);

	if (page)
		return page_folio(page);
	return NULL;
}

/**
 * vm_normal_page_pud() - Get the "struct page" associated with a PUD
 * @vma: The VMA mapping the @pud.
 * @addr: The address where the @pud is mapped.
 * @pud: The PUD.
 *
 * Get the "struct page" associated with a PUD. See __vm_normal_page()
 * for details on "normal" and "special" mappings.
 *
 * Return: Returns the "struct page" if this is a "normal" mapping. Returns
 *	   NULL if this is a "special" mapping.
 */
struct page *vm_normal_page_pud(struct vm_area_struct *vma,
		unsigned long addr, pud_t pud)
{
	return __vm_normal_page(vma, addr, pud_pfn(pud), pud_special(pud),
				pud_val(pud), PGTABLE_LEVEL_PUD);
}
#endif

/**
 * restore_exclusive_pte - Restore a device-exclusive entry
 * @vma: VMA covering @address
 * @folio: the mapped folio
 * @page: the mapped folio page
 * @address: the virtual address
 * @ptep: pte pointer into the locked page table mapping the folio page
 * @orig_pte: pte value at @ptep
 *
 * Restore a device-exclusive non-swap entry to an ordinary present pte.
 *
 * The folio and the page table must be locked, and MMU notifiers must have
 * been called to invalidate any (exclusive) device mappings.
 *
 * Locking the folio makes sure that anybody who just converted the pte to
 * a device-exclusive entry can map it into the device to make forward
 * progress without others converting it back until the folio was unlocked.
 *
 * If the folio lock ever becomes an issue, we can stop relying on the folio
 * lock; it might make some scenarios with heavy thrashing less likely to
 * make forward progress, but these scenarios might not be valid use cases.
 *
 * Note that the folio lock does not protect against all cases of concurrent
 * page table modifications (e.g., MADV_DONTNEED, mprotect), so device drivers
 * must use MMU notifiers to sync against any concurrent changes.
 */
static void restore_exclusive_pte(struct vm_area_struct *vma,
		struct folio *folio, struct page *page, unsigned long address,
		pte_t *ptep, pte_t orig_pte)
{
	pte_t pte;

	VM_WARN_ON_FOLIO(!folio_test_locked(folio), folio);

	pte = pte_mkold(mk_pte(page, READ_ONCE(vma->vm_page_prot)));
	if (pte_swp_soft_dirty(orig_pte))
		pte = pte_mksoft_dirty(pte);

	if (pte_swp_uffd_wp(orig_pte))
		pte = pte_mkuffd_wp(pte);

	if ((vma->vm_flags & VM_WRITE) &&
	    can_change_pte_writable(vma, address, pte)) {
		if (folio_test_dirty(folio))
			pte = pte_mkdirty(pte);
		pte = pte_mkwrite(pte, vma);
	}
	set_pte_at(vma->vm_mm, address, ptep, pte);

	/*
	 * No need to invalidate - it was non-present before. However
	 * secondary CPUs may have mappings that need invalidating.
	 */
	update_mmu_cache(vma, address, ptep);
}

/*
 * Tries to restore an exclusive pte if the page lock can be acquired without
 * sleeping.
 */
static int try_restore_exclusive_pte(struct vm_area_struct *vma,
		unsigned long addr, pte_t *ptep, pte_t orig_pte)
{
	const softleaf_t entry = softleaf_from_pte(orig_pte);
	struct page *page = softleaf_to_page(entry);
	struct folio *folio = page_folio(page);

	if (folio_trylock(folio)) {
		restore_exclusive_pte(vma, folio, page, addr, ptep, orig_pte);
		folio_unlock(folio);
		return 0;
	}

	return -EBUSY;
}

/*
 * copy one vm_area from one task to the other. Assumes the page tables
 * already present in the new task to be cleared in the whole range
 * covered by this vma.
 */

static unsigned long
copy_nonpresent_pte(struct mm_struct *dst_mm, struct mm_struct *src_mm,
		pte_t *dst_pte, pte_t *src_pte, struct vm_area_struct *dst_vma,
		struct vm_area_struct *src_vma, unsigned long addr, int *rss)
{
	vm_flags_t vm_flags = dst_vma->vm_flags;
	pte_t orig_pte = ptep_get(src_pte);
	softleaf_t entry = softleaf_from_pte(orig_pte);
	pte_t pte = orig_pte;
	struct folio *folio;
	struct page *page;

	if (likely(softleaf_is_swap(entry))) {
		if (swap_dup_entry_direct(entry) < 0)
			return -EIO;

		/* make sure dst_mm is on swapoff's mmlist. */
		if (unlikely(list_empty(&dst_mm->mmlist))) {
			spin_lock(&mmlist_lock);
			if (list_empty(&dst_mm->mmlist))
				list_add(&dst_mm->mmlist,
						&src_mm->mmlist);
			spin_unlock(&mmlist_lock);
		}
		/* Mark the swap entry as shared. */
		if (pte_swp_exclusive(orig_pte)) {
			pte = pte_swp_clear_exclusive(orig_pte);
			set_pte_at(src_mm, addr, src_pte, pte);
		}
		rss[MM_SWAPENTS]++;
	} else if (softleaf_is_migration(entry)) {
		folio = softleaf_to_folio(entry);

		rss[mm_counter(folio)]++;

		if (!softleaf_is_migration_read(entry) &&
				is_cow_mapping(vm_flags)) {
			/*
			 * COW mappings require pages in both parent and child
			 * to be set to read. A previously exclusive entry is
			 * now shared.
			 */
			entry = make_readable_migration_entry(
							swp_offset(entry));
			pte = softleaf_to_pte(entry);
			if (pte_swp_soft_dirty(orig_pte))
				pte = pte_swp_mksoft_dirty(pte);
			if (pte_swp_uffd_wp(orig_pte))
				pte = pte_swp_mkuffd_wp(pte);
			set_pte_at(src_mm, addr, src_pte, pte);
		}
	} else if (softleaf_is_device_private(entry)) {
		page = softleaf_to_page(entry);
		folio = page_folio(page);

		/*
		 * Update rss count even for unaddressable pages, as
		 * they should treated just like normal pages in this
		 * respect.
		 *
		 * We will likely want to have some new rss counters
		 * for unaddressable pages, at some point. But for now
		 * keep things as they are.
		 */
		folio_get(folio);
		rss[mm_counter(folio)]++;
		/* Cannot fail as these pages cannot get pinned. */
		folio_try_dup_anon_rmap_pte(folio, page, dst_vma, src_vma);

		/*
		 * We do not preserve soft-dirty information, because so
		 * far, checkpoint/restore is the only feature that
		 * requires that. And checkpoint/restore does not work
		 * when a device driver is involved (you cannot easily
		 * save and restore device driver state).
		 */
		if (softleaf_is_device_private_write(entry) &&
		    is_cow_mapping(vm_flags)) {
			entry = make_readable_device_private_entry(
							swp_offset(entry));
			pte = swp_entry_to_pte(entry);
			if (pte_swp_uffd_wp(orig_pte))
				pte = pte_swp_mkuffd_wp(pte);
			set_pte_at(src_mm, addr, src_pte, pte);
		}
	} else if (softleaf_is_device_exclusive(entry)) {
		/*
		 * Make device exclusive entries present by restoring the
		 * original entry then copying as for a present pte. Device
		 * exclusive entries currently only support private writable
		 * (ie. COW) mappings.
		 */
		VM_BUG_ON(!is_cow_mapping(src_vma->vm_flags));
		if (try_restore_exclusive_pte(src_vma, addr, src_pte, orig_pte))
			return -EBUSY;
		return -ENOENT;
	} else if (softleaf_is_marker(entry)) {
		pte_marker marker = copy_pte_marker(entry, dst_vma);

		if (marker)
			set_pte_at(dst_mm, addr, dst_pte,
				   make_pte_marker(marker));
		return 0;
	}
	if (!userfaultfd_wp(dst_vma))
		pte = pte_swp_clear_uffd_wp(pte);
	set_pte_at(dst_mm, addr, dst_pte, pte);
	return 0;
}

/*
 * Copy a present and normal page.
 *
 * NOTE! The usual case is that this isn't required;
 * instead, the caller can just increase the page refcount
 * and re-use the pte the traditional way.
 *
 * And if we need a pre-allocated page but don't yet have
 * one, return a negative error to let the preallocation
 * code know so that it can do so outside the page table
 * lock.
 */
static inline int
copy_present_page(struct vm_area_struct *dst_vma, struct vm_area_struct *src_vma,
		  pte_t *dst_pte, pte_t *src_pte, unsigned long addr, int *rss,
		  struct folio **prealloc, struct page *page)
{
	struct folio *new_folio;
	pte_t pte;

	new_folio = *prealloc;
	if (!new_folio)
		return -EAGAIN;

	/*
	 * We have a prealloc page, all good!  Take it
	 * over and copy the page & arm it.
	 */

	if (copy_mc_user_highpage(&new_folio->page, page, addr, src_vma))
		return -EHWPOISON;

	*prealloc = NULL;
	__folio_mark_uptodate(new_folio);
	folio_add_new_anon_rmap(new_folio, dst_vma, addr, RMAP_EXCLUSIVE);
	folio_add_lru_vma(new_folio, dst_vma);
	rss[MM_ANONPAGES]++;

	/* All done, just insert the new page copy in the child */
	pte = folio_mk_pte(new_folio, dst_vma->vm_page_prot);
	pte = maybe_mkwrite(pte_mkdirty(pte), dst_vma);
	if (userfaultfd_pte_wp(dst_vma, ptep_get(src_pte)))
		/* Uffd-wp needs to be delivered to dest pte as well */
		pte = pte_mkuffd_wp(pte);
	set_pte_at(dst_vma->vm_mm, addr, dst_pte, pte);
	return 0;
}

static __always_inline void __copy_present_ptes(struct vm_area_struct *dst_vma,
		struct vm_area_struct *src_vma, pte_t *dst_pte, pte_t *src_pte,
		pte_t pte, unsigned long addr, int nr)
{
	struct mm_struct *src_mm = src_vma->vm_mm;

	/* If it's a COW mapping, write protect it both processes. */
	if (is_cow_mapping(src_vma->vm_flags) && pte_write(pte)) {
		wrprotect_ptes(src_mm, addr, src_pte, nr);
		pte = pte_wrprotect(pte);
	}

	/* If it's a shared mapping, mark it clean in the child. */
	if (src_vma->vm_flags & VM_SHARED)
		pte = pte_mkclean(pte);
	pte = pte_mkold(pte);

	if (!userfaultfd_wp(dst_vma))
		pte = pte_clear_uffd_wp(pte);

	set_ptes(dst_vma->vm_mm, addr, dst_pte, pte, nr);
}

/*
 * Copy one present PTE, trying to batch-process subsequent PTEs that map
 * consecutive pages of the same folio by copying them as well.
 *
 * Returns -EAGAIN if one preallocated page is required to copy the next PTE.
 * Otherwise, returns the number of copied PTEs (at least 1).
 */
static inline int
copy_present_ptes(struct vm_area_struct *dst_vma, struct vm_area_struct *src_vma,
		 pte_t *dst_pte, pte_t *src_pte, pte_t pte, unsigned long addr,
		 int max_nr, int *rss, struct folio **prealloc)
{
	fpb_t flags = FPB_MERGE_WRITE;
	struct page *page;
	struct folio *folio;
	int err, nr;

	page = vm_normal_page(src_vma, addr, pte);
	if (unlikely(!page))
		goto copy_pte;

	folio = page_folio(page);

	/*
	 * If we likely have to copy, just don't bother with batching. Make
	 * sure that the common "small folio" case is as fast as possible
	 * by keeping the batching logic separate.
	 */
	if (unlikely(!*prealloc && folio_test_large(folio) && max_nr != 1)) {
		if (!(src_vma->vm_flags & VM_SHARED))
			flags |= FPB_RESPECT_DIRTY;
		if (vma_soft_dirty_enabled(src_vma))
			flags |= FPB_RESPECT_SOFT_DIRTY;

		nr = folio_pte_batch_flags(folio, src_vma, src_pte, &pte, max_nr, flags);
		folio_ref_add(folio, nr);
		if (folio_test_anon(folio)) {
			if (unlikely(folio_try_dup_anon_rmap_ptes(folio, page,
								  nr, dst_vma, src_vma))) {
				folio_ref_sub(folio, nr);
				return -EAGAIN;
			}
			rss[MM_ANONPAGES] += nr;
			VM_WARN_ON_FOLIO(PageAnonExclusive(page), folio);
		} else {
			folio_dup_file_rmap_ptes(folio, page, nr, dst_vma);
			rss[mm_counter_file(folio)] += nr;
		}
		__copy_present_ptes(dst_vma, src_vma, dst_pte, src_pte, pte,
				    addr, nr);
		return nr;
	}

	folio_get(folio);
	if (folio_test_anon(folio)) {
		/*
		 * If this page may have been pinned by the parent process,
		 * copy the page immediately for the child so that we'll always
		 * guarantee the pinned page won't be randomly replaced in the
		 * future.
		 */
		if (unlikely(folio_try_dup_anon_rmap_pte(folio, page, dst_vma, src_vma))) {
			/* Page may be pinned, we have to copy. */
			folio_put(folio);
			err = copy_present_page(dst_vma, src_vma, dst_pte, src_pte,
						addr, rss, prealloc, page);
			return err ? err : 1;
		}
		rss[MM_ANONPAGES]++;
		VM_WARN_ON_FOLIO(PageAnonExclusive(page), folio);
	} else {
		folio_dup_file_rmap_pte(folio, page, dst_vma);
		rss[mm_counter_file(folio)]++;
	}

copy_pte:
	__copy_present_ptes(dst_vma, src_vma, dst_pte, src_pte, pte, addr, 1);
	return 1;
}

static inline struct folio *folio_prealloc(struct mm_struct *src_mm,
		struct vm_area_struct *vma, unsigned long addr, bool need_zero)
{
	struct folio *new_folio;

	if (need_zero)
		new_folio = vma_alloc_zeroed_movable_folio(vma, addr);
	else
		new_folio = vma_alloc_folio(GFP_HIGHUSER_MOVABLE, 0, vma, addr);

	if (!new_folio)
		return NULL;

	if (mem_cgroup_charge(new_folio, src_mm, GFP_KERNEL)) {
		folio_put(new_folio);
		return NULL;
	}
	folio_throttle_swaprate(new_folio, GFP_KERNEL);

	return new_folio;
}

static int
copy_pte_range(struct vm_area_struct *dst_vma, struct vm_area_struct *src_vma,
	       pmd_t *dst_pmd, pmd_t *src_pmd, unsigned long addr,
	       unsigned long end)
{
	struct mm_struct *dst_mm = dst_vma->vm_mm;
	struct mm_struct *src_mm = src_vma->vm_mm;
	pte_t *orig_src_pte, *orig_dst_pte;
	pte_t *src_pte, *dst_pte;
	pmd_t dummy_pmdval;
	pte_t ptent;
	spinlock_t *src_ptl, *dst_ptl;
	int progress, max_nr, ret = 0;
	int rss[NR_MM_COUNTERS];
	softleaf_t entry = softleaf_mk_none();
	struct folio *prealloc = NULL;
	int nr;

again:
	progress = 0;
	init_rss_vec(rss);

	/*
	 * copy_pmd_range()'s prior pmd_none_or_clear_bad(src_pmd), and the
	 * error handling here, assume that exclusive mmap_lock on dst and src
	 * protects anon from unexpected THP transitions; with shmem and file
	 * protected by mmap_lock-less collapse skipping areas with anon_vma
	 * (whereas vma_needs_copy() skips areas without anon_vma).  A rework
	 * can remove such assumptions later, but this is good enough for now.
	 */
	dst_pte = pte_alloc_map_lock(dst_mm, dst_pmd, addr, &dst_ptl);
	if (!dst_pte) {
		ret = -ENOMEM;
		goto out;
	}

	/*
	 * We already hold the exclusive mmap_lock, the copy_pte_range() and
	 * retract_page_tables() are using vma->anon_vma to be exclusive, so
	 * the PTE page is stable, and there is no need to get pmdval and do
	 * pmd_same() check.
	 */
	src_pte = pte_offset_map_rw_nolock(src_mm, src_pmd, addr, &dummy_pmdval,
					   &src_ptl);
	if (!src_pte) {
		pte_unmap_unlock(dst_pte, dst_ptl);
		/* ret == 0 */
		goto out;
	}
	spin_lock_nested(src_ptl, SINGLE_DEPTH_NESTING);
	orig_src_pte = src_pte;
	orig_dst_pte = dst_pte;
	lazy_mmu_mode_enable();

	do {
		nr = 1;

		/*
		 * We are holding two locks at this point - either of them
		 * could generate latencies in another task on another CPU.
		 */
		if (progress >= 32) {
			progress = 0;
			if (need_resched() ||
			    spin_needbreak(src_ptl) || spin_needbreak(dst_ptl))
				break;
		}
		ptent = ptep_get(src_pte);
		if (pte_none(ptent)) {
			progress++;
			continue;
		}
		if (unlikely(!pte_present(ptent))) {
			ret = copy_nonpresent_pte(dst_mm, src_mm,
						  dst_pte, src_pte,
						  dst_vma, src_vma,
						  addr, rss);
			if (ret == -EIO) {
				entry = softleaf_from_pte(ptep_get(src_pte));
				break;
			} else if (ret == -EBUSY) {
				break;
			} else if (!ret) {
				progress += 8;
				continue;
			}
			ptent = ptep_get(src_pte);
			VM_WARN_ON_ONCE(!pte_present(ptent));

			/*
			 * Device exclusive entry restored, continue by copying
			 * the now present pte.
			 */
			WARN_ON_ONCE(ret != -ENOENT);
		}
		/* copy_present_ptes() will clear `*prealloc' if consumed */
		max_nr = (end - addr) / PAGE_SIZE;
		ret = copy_present_ptes(dst_vma, src_vma, dst_pte, src_pte,
					ptent, addr, max_nr, rss, &prealloc);
		/*
		 * If we need a pre-allocated page for this pte, drop the
		 * locks, allocate, and try again.
		 * If copy failed due to hwpoison in source page, break out.
		 */
		if (unlikely(ret == -EAGAIN || ret == -EHWPOISON))
			break;
		if (unlikely(prealloc)) {
			/*
			 * pre-alloc page cannot be reused by next time so as
			 * to strictly follow mempolicy (e.g., alloc_page_vma()
			 * will allocate page according to address).  This
			 * could only happen if one pinned pte changed.
			 */
			folio_put(prealloc);
			prealloc = NULL;
		}
		nr = ret;
		progress += 8 * nr;
	} while (dst_pte += nr, src_pte += nr, addr += PAGE_SIZE * nr,
		 addr != end);

	lazy_mmu_mode_disable();
	pte_unmap_unlock(orig_src_pte, src_ptl);
	add_mm_rss_vec(dst_mm, rss);
	pte_unmap_unlock(orig_dst_pte, dst_ptl);
	cond_resched();

	if (ret == -EIO) {
		VM_WARN_ON_ONCE(!entry.val);
		if (add_swap_count_continuation(entry, GFP_KERNEL) < 0) {
			ret = -ENOMEM;
			goto out;
		}
		entry.val = 0;
	} else if (ret == -EBUSY || unlikely(ret == -EHWPOISON)) {
		goto out;
	} else if (ret ==  -EAGAIN) {
		prealloc = folio_prealloc(src_mm, src_vma, addr, false);
		if (!prealloc)
			return -ENOMEM;
	} else if (ret < 0) {
		VM_WARN_ON_ONCE(1);
	}

	/* We've captured and resolved the error. Reset, try again. */
	ret = 0;

	if (addr != end)
		goto again;
out:
	if (unlikely(prealloc))
		folio_put(prealloc);
	return ret;
}

static inline int
copy_pmd_range(struct vm_area_struct *dst_vma, struct vm_area_struct *src_vma,
	       pud_t *dst_pud, pud_t *src_pud, unsigned long addr,
	       unsigned long end)
{
	struct mm_struct *dst_mm = dst_vma->vm_mm;
	struct mm_struct *src_mm = src_vma->vm_mm;
	pmd_t *src_pmd, *dst_pmd;
	unsigned long next;

	dst_pmd = pmd_alloc(dst_mm, dst_pud, addr);
	if (!dst_pmd)
		return -ENOMEM;
	src_pmd = pmd_offset(src_pud, addr);
	do {
		next = pmd_addr_end(addr, end);
		if (pmd_is_huge(*src_pmd)) {
			int err;

			VM_BUG_ON_VMA(next-addr != HPAGE_PMD_SIZE, src_vma);
			err = copy_huge_pmd(dst_mm, src_mm, dst_pmd, src_pmd,
					    addr, dst_vma, src_vma);
			if (err == -ENOMEM)
				return -ENOMEM;
			if (!err)
				continue;
			/* fall through */
		}
		if (pmd_none_or_clear_bad(src_pmd))
			continue;
		if (copy_pte_range(dst_vma, src_vma, dst_pmd, src_pmd,
				   addr, next))
			return -ENOMEM;
	} while (dst_pmd++, src_pmd++, addr = next, addr != end);
	return 0;
}

static inline int
copy_pud_range(struct vm_area_struct *dst_vma, struct vm_area_struct *src_vma,
	       p4d_t *dst_p4d, p4d_t *src_p4d, unsigned long addr,
	       unsigned long end)
{
	struct mm_struct *dst_mm = dst_vma->vm_mm;
	struct mm_struct *src_mm = src_vma->vm_mm;
	pud_t *src_pud, *dst_pud;
	unsigned long next;

	dst_pud = pud_alloc(dst_mm, dst_p4d, addr);
	if (!dst_pud)
		return -ENOMEM;
	src_pud = pud_offset(src_p4d, addr);
	do {
		next = pud_addr_end(addr, end);
		if (pud_trans_huge(*src_pud)) {
			int err;

			VM_BUG_ON_VMA(next-addr != HPAGE_PUD_SIZE, src_vma);
			err = copy_huge_pud(dst_mm, src_mm,
					    dst_pud, src_pud, addr, src_vma);
			if (err == -ENOMEM)
				return -ENOMEM;
			if (!err)
				continue;
			/* fall through */
		}
		if (pud_none_or_clear_bad(src_pud))
			continue;
		if (copy_pmd_range(dst_vma, src_vma, dst_pud, src_pud,
				   addr, next))
			return -ENOMEM;
	} while (dst_pud++, src_pud++, addr = next, addr != end);
	return 0;
}

static inline int
copy_p4d_range(struct vm_area_struct *dst_vma, struct vm_area_struct *src_vma,
	       pgd_t *dst_pgd, pgd_t *src_pgd, unsigned long addr,
	       unsigned long end)
{
	struct mm_struct *dst_mm = dst_vma->vm_mm;
	p4d_t *src_p4d, *dst_p4d;
	unsigned long next;

	dst_p4d = p4d_alloc(dst_mm, dst_pgd, addr);
	if (!dst_p4d)
		return -ENOMEM;
	src_p4d = p4d_offset(src_pgd, addr);
	do {
		next = p4d_addr_end(addr, end);
		if (p4d_none_or_clear_bad(src_p4d))
			continue;
		if (copy_pud_range(dst_vma, src_vma, dst_p4d, src_p4d,
				   addr, next))
			return -ENOMEM;
	} while (dst_p4d++, src_p4d++, addr = next, addr != end);
	return 0;
}

/*
 * Return true if the vma needs to copy the pgtable during this fork().  Return
 * false when we can speed up fork() by allowing lazy page faults later until
 * when the child accesses the memory range.
 */
static bool
vma_needs_copy(struct vm_area_struct *dst_vma, struct vm_area_struct *src_vma)
{
	/*
	 * We check against dst_vma as while sane VMA flags will have been
	 * copied, VM_UFFD_WP may be set only on dst_vma.
	 */
	if (dst_vma->vm_flags & VM_COPY_ON_FORK)
		return true;
	/*
	 * The presence of an anon_vma indicates an anonymous VMA has page
	 * tables which naturally cannot be reconstituted on page fault.
	 */
	if (src_vma->anon_vma)
		return true;

	/*
	 * Don't copy ptes where a page fault will fill them correctly.  Fork
	 * becomes much lighter when there are big shared or private readonly
	 * mappings. The tradeoff is that copy_page_range is more efficient
	 * than faulting.
	 */
	return false;
}

int
copy_page_range(struct vm_area_struct *dst_vma, struct vm_area_struct *src_vma)
{
	pgd_t *src_pgd, *dst_pgd;
	unsigned long addr = src_vma->vm_start;
	unsigned long end = src_vma->vm_end;
	struct mm_struct *dst_mm = dst_vma->vm_mm;
	struct mm_struct *src_mm = src_vma->vm_mm;
	struct mmu_notifier_range range;
	unsigned long next;
	bool is_cow;
	int ret;

	if (!vma_needs_copy(dst_vma, src_vma))
		return 0;

	if (is_vm_hugetlb_page(src_vma))
		return copy_hugetlb_page_range(dst_mm, src_mm, dst_vma, src_vma);

	/*
	 * We need to invalidate the secondary MMU mappings only when
	 * there could be a permission downgrade on the ptes of the
	 * parent mm. And a permission downgrade will only happen if
	 * is_cow_mapping() returns true.
	 */
	is_cow = is_cow_mapping(src_vma->vm_flags);

	if (is_cow) {
		mmu_notifier_range_init(&range, MMU_NOTIFY_PROTECTION_PAGE,
					0, src_mm, addr, end);
		mmu_notifier_invalidate_range_start(&range);
		/*
		 * Disabling preemption is not needed for the write side, as
		 * the read side doesn't spin, but goes to the mmap_lock.
		 *
		 * Use the raw variant of the seqcount_t write API to avoid
		 * lockdep complaining about preemptibility.
		 */
		vma_assert_write_locked(src_vma);
		raw_write_seqcount_begin(&src_mm->write_protect_seq);
	}

	ret = 0;
	dst_pgd = pgd_offset(dst_mm, addr);
	src_pgd = pgd_offset(src_mm, addr);
	do {
		next = pgd_addr_end(addr, end);
		if (pgd_none_or_clear_bad(src_pgd))
			continue;
		if (unlikely(copy_p4d_range(dst_vma, src_vma, dst_pgd, src_pgd,
					    addr, next))) {
			ret = -ENOMEM;
			break;
		}
	} while (dst_pgd++, src_pgd++, addr = next, addr != end);

	if (is_cow) {
		raw_write_seqcount_end(&src_mm->write_protect_seq);
		mmu_notifier_invalidate_range_end(&range);
	}
	return ret;
}

/* Whether we should zap all COWed (private) pages too */
static inline bool should_zap_cows(struct zap_details *details)
{
	/* By default, zap all pages */
	if (!details || details->reclaim_pt)
		return true;

	/* Or, we zap COWed pages only if the caller wants to */
	return details->even_cows;
}

/* Decides whether we should zap this folio with the folio pointer specified */
static inline bool should_zap_folio(struct zap_details *details,
				    struct folio *folio)
{
	/* If we can make a decision without *folio.. */
	if (should_zap_cows(details))
		return true;

	/* Otherwise we should only zap non-anon folios */
	return !folio_test_anon(folio);
}

static inline bool zap_drop_markers(struct zap_details *details)
{
	if (!details)
		return false;

	return details->zap_flags & ZAP_FLAG_DROP_MARKER;
}

/*
 * This function makes sure that we'll replace the none pte with an uffd-wp
 * swap special pte marker when necessary. Must be with the pgtable lock held.
 *
 * Returns true if uffd-wp ptes was installed, false otherwise.
 */
static inline bool
zap_install_uffd_wp_if_needed(struct vm_area_struct *vma,
			      unsigned long addr, pte_t *pte, int nr,
			      struct zap_details *details, pte_t pteval)
{
	bool was_installed = false;

	if (!uffd_supports_wp_marker())
		return false;

	/* Zap on anonymous always means dropping everything */
	if (vma_is_anonymous(vma))
		return false;

	if (zap_drop_markers(details))
		return false;

	for (;;) {
		/* the PFN in the PTE is irrelevant. */
		if (pte_install_uffd_wp_if_needed(vma, addr, pte, pteval))
			was_installed = true;
		if (--nr == 0)
			break;
		pte++;
		addr += PAGE_SIZE;
	}

	return was_installed;
}

static __always_inline void zap_present_folio_ptes(struct mmu_gather *tlb,
		struct vm_area_struct *vma, struct folio *folio,
		struct page *page, pte_t *pte, pte_t ptent, unsigned int nr,
		unsigned long addr, struct zap_details *details, int *rss,
		bool *force_flush, bool *force_break, bool *any_skipped)
{
	struct mm_struct *mm = tlb->mm;
	bool delay_rmap = false;

	if (!folio_test_anon(folio)) {
		ptent = get_and_clear_full_ptes(mm, addr, pte, nr, tlb->fullmm);
		if (pte_dirty(ptent)) {
			folio_mark_dirty(folio);
			if (tlb_delay_rmap(tlb)) {
				delay_rmap = true;
				*force_flush = true;
			}
		}
		if (pte_young(ptent) && likely(vma_has_recency(vma)))
			folio_mark_accessed(folio);
		rss[mm_counter(folio)] -= nr;
	} else {
		/* We don't need up-to-date accessed/dirty bits. */
		clear_full_ptes(mm, addr, pte, nr, tlb->fullmm);
		rss[MM_ANONPAGES] -= nr;
	}
	/* Checking a single PTE in a batch is sufficient. */
	arch_check_zapped_pte(vma, ptent);
	tlb_remove_tlb_entries(tlb, pte, nr, addr);
	if (unlikely(userfaultfd_pte_wp(vma, ptent)))
		*any_skipped = zap_install_uffd_wp_if_needed(vma, addr, pte,
							     nr, details, ptent);

	if (!delay_rmap) {
		folio_remove_rmap_ptes(folio, page, nr, vma);

		if (unlikely(folio_mapcount(folio) < 0))
			print_bad_pte(vma, addr, ptent, page);
	}
	if (unlikely(__tlb_remove_folio_pages(tlb, page, nr, delay_rmap))) {
		*force_flush = true;
		*force_break = true;
	}
}

/*
 * Zap or skip at least one present PTE, trying to batch-process subsequent
 * PTEs that map consecutive pages of the same folio.
 *
 * Returns the number of processed (skipped or zapped) PTEs (at least 1).
 */
static inline int zap_present_ptes(struct mmu_gather *tlb,
		struct vm_area_struct *vma, pte_t *pte, pte_t ptent,
		unsigned int max_nr, unsigned long addr,
		struct zap_details *details, int *rss, bool *force_flush,
		bool *force_break, bool *any_skipped)
{
	struct mm_struct *mm = tlb->mm;
	struct folio *folio;
	struct page *page;
	int nr;

	page = vm_normal_page(vma, addr, ptent);
	if (!page) {
		/* We don't need up-to-date accessed/dirty bits. */
		ptep_get_and_clear_full(mm, addr, pte, tlb->fullmm);
		arch_check_zapped_pte(vma, ptent);
		tlb_remove_tlb_entry(tlb, pte, addr);
		if (userfaultfd_pte_wp(vma, ptent))
			*any_skipped = zap_install_uffd_wp_if_needed(vma, addr,
						pte, 1, details, ptent);
		ksm_might_unmap_zero_page(mm, ptent);
		return 1;
	}

	folio = page_folio(page);
	if (unlikely(!should_zap_folio(details, folio))) {
		*any_skipped = true;
		return 1;
	}

	/*
	 * Make sure that the common "small folio" case is as fast as possible
	 * by keeping the batching logic separate.
	 */
	if (unlikely(folio_test_large(folio) && max_nr != 1)) {
		nr = folio_pte_batch(folio, pte, ptent, max_nr);
		zap_present_folio_ptes(tlb, vma, folio, page, pte, ptent, nr,
				       addr, details, rss, force_flush,
				       force_break, any_skipped);
		return nr;
	}
	zap_present_folio_ptes(tlb, vma, folio, page, pte, ptent, 1, addr,
			       details, rss, force_flush, force_break, any_skipped);
	return 1;
}

static inline int zap_nonpresent_ptes(struct mmu_gather *tlb,
		struct vm_area_struct *vma, pte_t *pte, pte_t ptent,
		unsigned int max_nr, unsigned long addr,
		struct zap_details *details, int *rss, bool *any_skipped)
{
	softleaf_t entry;
	int nr = 1;

	*any_skipped = true;
	entry = softleaf_from_pte(ptent);
	if (softleaf_is_device_private(entry) ||
	    softleaf_is_device_exclusive(entry)) {
		struct page *page = softleaf_to_page(entry);
		struct folio *folio = page_folio(page);

		if (unlikely(!should_zap_folio(details, folio)))
			return 1;
		/*
		 * Both device private/exclusive mappings should only
		 * work with anonymous page so far, so we don't need to
		 * consider uffd-wp bit when zap. For more information,
		 * see zap_install_uffd_wp_if_needed().
		 */
		WARN_ON_ONCE(!vma_is_anonymous(vma));
		rss[mm_counter(folio)]--;
		folio_remove_rmap_pte(folio, page, vma);
		folio_put(folio);
	} else if (softleaf_is_swap(entry)) {
		/* Genuine swap entries, hence a private anon pages */
		if (!should_zap_cows(details))
			return 1;

		nr = swap_pte_batch(pte, max_nr, ptent);
		rss[MM_SWAPENTS] -= nr;
		swap_put_entries_direct(entry, nr);
	} else if (softleaf_is_migration(entry)) {
		struct folio *folio = softleaf_to_folio(entry);

		if (!should_zap_folio(details, folio))
			return 1;
		rss[mm_counter(folio)]--;
	} else if (softleaf_is_uffd_wp_marker(entry)) {
		/*
		 * For anon: always drop the marker; for file: only
		 * drop the marker if explicitly requested.
		 */
		if (!vma_is_anonymous(vma) && !zap_drop_markers(details))
			return 1;
	} else if (softleaf_is_guard_marker(entry)) {
		/*
		 * Ordinary zapping should not remove guard PTE
		 * markers. Only do so if we should remove PTE markers
		 * in general.
		 */
		if (!zap_drop_markers(details))
			return 1;
	} else if (softleaf_is_hwpoison(entry) ||
		   softleaf_is_poison_marker(entry)) {
		if (!should_zap_cows(details))
			return 1;
	} else {
		/* We should have covered all the swap entry types */
		pr_alert("unrecognized swap entry 0x%lx\n", entry.val);
		WARN_ON_ONCE(1);
	}
	clear_not_present_full_ptes(vma->vm_mm, addr, pte, nr, tlb->fullmm);
	*any_skipped = zap_install_uffd_wp_if_needed(vma, addr, pte, nr, details, ptent);

	return nr;
}

static inline int do_zap_pte_range(struct mmu_gather *tlb,
				   struct vm_area_struct *vma, pte_t *pte,
				   unsigned long addr, unsigned long end,
				   struct zap_details *details, int *rss,
				   bool *force_flush, bool *force_break,
				   bool *any_skipped)
{
	pte_t ptent = ptep_get(pte);
	int max_nr = (end - addr) / PAGE_SIZE;
	int nr = 0;

	/* Skip all consecutive none ptes */
	if (pte_none(ptent)) {
		for (nr = 1; nr < max_nr; nr++) {
			ptent = ptep_get(pte + nr);
			if (!pte_none(ptent))
				break;
		}
		max_nr -= nr;
		if (!max_nr)
			return nr;
		pte += nr;
		addr += nr * PAGE_SIZE;
	}

	if (pte_present(ptent))
		nr += zap_present_ptes(tlb, vma, pte, ptent, max_nr, addr,
				       details, rss, force_flush, force_break,
				       any_skipped);
	else
		nr += zap_nonpresent_ptes(tlb, vma, pte, ptent, max_nr, addr,
					  details, rss, any_skipped);

	return nr;
}

static bool pte_table_reclaim_possible(unsigned long start, unsigned long end,
		struct zap_details *details)
{
	if (!IS_ENABLED(CONFIG_PT_RECLAIM))
		return false;
	/* Only zap if we are allowed to and cover the full page table. */
	return details && details->reclaim_pt && (end - start >= PMD_SIZE);
}

static bool zap_empty_pte_table(struct mm_struct *mm, pmd_t *pmd,
		spinlock_t *ptl, pmd_t *pmdval)
{
	spinlock_t *pml = pmd_lockptr(mm, pmd);

	if (ptl != pml && !spin_trylock(pml))
		return false;

	*pmdval = pmdp_get(pmd);
	pmd_clear(pmd);
	if (ptl != pml)
		spin_unlock(pml);
	return true;
}

static bool zap_pte_table_if_empty(struct mm_struct *mm, pmd_t *pmd,
		unsigned long addr, pmd_t *pmdval)
{
	spinlock_t *pml, *ptl = NULL;
	pte_t *start_pte, *pte;
	int i;

	pml = pmd_lock(mm, pmd);
	start_pte = pte_offset_map_rw_nolock(mm, pmd, addr, pmdval, &ptl);
	if (!start_pte)
		goto out_ptl;
	if (ptl != pml)
		spin_lock_nested(ptl, SINGLE_DEPTH_NESTING);

	for (i = 0, pte = start_pte; i < PTRS_PER_PTE; i++, pte++) {
		if (!pte_none(ptep_get(pte)))
			goto out_ptl;
	}
	pte_unmap(start_pte);

	pmd_clear(pmd);

	if (ptl != pml)
		spin_unlock(ptl);
	spin_unlock(pml);
	return true;
out_ptl:
	if (start_pte)
		pte_unmap_unlock(start_pte, ptl);
	if (ptl != pml)
		spin_unlock(pml);
	return false;
}

static unsigned long zap_pte_range(struct mmu_gather *tlb,
				struct vm_area_struct *vma, pmd_t *pmd,
				unsigned long addr, unsigned long end,
				struct zap_details *details)
{
	bool can_reclaim_pt = pte_table_reclaim_possible(addr, end, details);
	bool force_flush = false, force_break = false;
	struct mm_struct *mm = tlb->mm;
	int rss[NR_MM_COUNTERS];
	spinlock_t *ptl;
	pte_t *start_pte;
	pte_t *pte;
	pmd_t pmdval;
	unsigned long start = addr;
	bool direct_reclaim = true;
	int nr;

retry:
	tlb_change_page_size(tlb, PAGE_SIZE);
	init_rss_vec(rss);
	start_pte = pte = pte_offset_map_lock(mm, pmd, addr, &ptl);
	if (!pte)
		return addr;

	flush_tlb_batched_pending(mm);
	lazy_mmu_mode_enable();
	do {
		bool any_skipped = false;

		if (need_resched()) {
			direct_reclaim = false;
			break;
		}

		nr = do_zap_pte_range(tlb, vma, pte, addr, end, details, rss,
				      &force_flush, &force_break, &any_skipped);
		if (any_skipped)
			can_reclaim_pt = false;
		if (unlikely(force_break)) {
			addr += nr * PAGE_SIZE;
			direct_reclaim = false;
			break;
		}
	} while (pte += nr, addr += PAGE_SIZE * nr, addr != end);

	/*
	 * Fast path: try to hold the pmd lock and unmap the PTE page.
	 *
	 * If the pte lock was released midway (retry case), or if the attempt
	 * to hold the pmd lock failed, then we need to recheck all pte entries
	 * to ensure they are still none, thereby preventing the pte entries
	 * from being repopulated by another thread.
	 */
	if (can_reclaim_pt && direct_reclaim && addr == end)
		direct_reclaim = zap_empty_pte_table(mm, pmd, ptl, &pmdval);

	add_mm_rss_vec(mm, rss);
	lazy_mmu_mode_disable();

	/* Do the actual TLB flush before dropping ptl */
	if (force_flush) {
		tlb_flush_mmu_tlbonly(tlb);
		tlb_flush_rmaps(tlb, vma);
	}
	pte_unmap_unlock(start_pte, ptl);

	/*
	 * If we forced a TLB flush (either due to running out of
	 * batch buffers or because we needed to flush dirty TLB
	 * entries before releasing the ptl), free the batched
	 * memory too. Come back again if we didn't do everything.
	 */
	if (force_flush)
		tlb_flush_mmu(tlb);

	if (addr != end) {
		cond_resched();
		force_flush = false;
		force_break = false;
		goto retry;
	}

	if (can_reclaim_pt) {
		if (direct_reclaim || zap_pte_table_if_empty(mm, pmd, start, &pmdval)) {
			pte_free_tlb(tlb, pmd_pgtable(pmdval), addr);
			mm_dec_nr_ptes(mm);
		}
	}

	return addr;
}

static inline unsigned long zap_pmd_range(struct mmu_gather *tlb,
				struct vm_area_struct *vma, pud_t *pud,
				unsigned long addr, unsigned long end,
				struct zap_details *details)
{
	pmd_t *pmd;
	unsigned long next;

	pmd = pmd_offset(pud, addr);
	do {
		next = pmd_addr_end(addr, end);
		if (pmd_is_huge(*pmd)) {
			if (next - addr != HPAGE_PMD_SIZE)
				__split_huge_pmd(vma, pmd, addr, false);
			else if (zap_huge_pmd(tlb, vma, pmd, addr)) {
				addr = next;
				continue;
			}
			/* fall through */
		} else if (details && details->single_folio &&
			   folio_test_pmd_mappable(details->single_folio) &&
			   next - addr == HPAGE_PMD_SIZE && pmd_none(*pmd)) {
			spinlock_t *ptl = pmd_lock(tlb->mm, pmd);
			/*
			 * Take and drop THP pmd lock so that we cannot return
			 * prematurely, while zap_huge_pmd() has cleared *pmd,
			 * but not yet decremented compound_mapcount().
			 */
			spin_unlock(ptl);
		}
		if (pmd_none(*pmd)) {
			addr = next;
			continue;
		}
		addr = zap_pte_range(tlb, vma, pmd, addr, next, details);
		if (addr != next)
			pmd--;
	} while (pmd++, cond_resched(), addr != end);

	return addr;
}

static inline unsigned long zap_pud_range(struct mmu_gather *tlb,
				struct vm_area_struct *vma, p4d_t *p4d,
				unsigned long addr, unsigned long end,
				struct zap_details *details)
{
	pud_t *pud;
	unsigned long next;

	pud = pud_offset(p4d, addr);
	do {
		next = pud_addr_end(addr, end);
		if (pud_trans_huge(*pud)) {
			if (next - addr != HPAGE_PUD_SIZE)
				split_huge_pud(vma, pud, addr);
			else if (zap_huge_pud(tlb, vma, pud, addr))
				goto next;
			/* fall through */
		}
		if (pud_none_or_clear_bad(pud))
			continue;
		next = zap_pmd_range(tlb, vma, pud, addr, next, details);
next:
		cond_resched();
	} while (pud++, addr = next, addr != end);

	return addr;
}

static inline unsigned long zap_p4d_range(struct mmu_gather *tlb,
				struct vm_area_struct *vma, pgd_t *pgd,
				unsigned long addr, unsigned long end,
				struct zap_details *details)
{
	p4d_t *p4d;
	unsigned long next;

	p4d = p4d_offset(pgd, addr);
	do {
		next = p4d_addr_end(addr, end);
		if (p4d_none_or_clear_bad(p4d))
			continue;
		next = zap_pud_range(tlb, vma, p4d, addr, next, details);
	} while (p4d++, addr = next, addr != end);

	return addr;
}

void unmap_page_range(struct mmu_gather *tlb,
			     struct vm_area_struct *vma,
			     unsigned long addr, unsigned long end,
			     struct zap_details *details)
{
	pgd_t *pgd;
	unsigned long next;

	BUG_ON(addr >= end);
	tlb_start_vma(tlb, vma);
	pgd = pgd_offset(vma->vm_mm, addr);
	do {
		next = pgd_addr_end(addr, end);
		if (pgd_none_or_clear_bad(pgd))
			continue;
		next = zap_p4d_range(tlb, vma, pgd, addr, next, details);
	} while (pgd++, addr = next, addr != end);
	tlb_end_vma(tlb, vma);
}


static void unmap_single_vma(struct mmu_gather *tlb,
		struct vm_area_struct *vma, unsigned long start_addr,
		unsigned long end_addr, struct zap_details *details)
{
	unsigned long start = max(vma->vm_start, start_addr);
	unsigned long end;

	if (start >= vma->vm_end)
		return;
	end = min(vma->vm_end, end_addr);
	if (end <= vma->vm_start)
		return;

	if (vma->vm_file)
		uprobe_munmap(vma, start, end);

	if (start != end) {
		if (unlikely(is_vm_hugetlb_page(vma))) {
			/*
			 * It is undesirable to test vma->vm_file as it
			 * should be non-null for valid hugetlb area.
			 * However, vm_file will be NULL in the error
			 * cleanup path of mmap_region. When
			 * hugetlbfs ->mmap method fails,
			 * mmap_region() nullifies vma->vm_file
			 * before calling this function to clean up.
			 * Since no pte has actually been setup, it is
			 * safe to do nothing in this case.
			 */
			if (vma->vm_file) {
				zap_flags_t zap_flags = details ?
				    details->zap_flags : 0;
				__unmap_hugepage_range(tlb, vma, start, end,
							     NULL, zap_flags);
			}
		} else
			unmap_page_range(tlb, vma, start, end, details);
	}
}

/**
 * unmap_vmas - unmap a range of memory covered by a list of vma's
 * @tlb: address of the caller's struct mmu_gather
 * @unmap: The unmap_desc
 *
 * Unmap all pages in the vma list.
 *
 * Only addresses between `start' and `end' will be unmapped.
 *
 * The VMA list must be sorted in ascending virtual address order.
 *
 * unmap_vmas() assumes that the caller will flush the whole unmapped address
 * range after unmap_vmas() returns.  So the only responsibility here is to
 * ensure that any thus-far unmapped pages are flushed before unmap_vmas()
 * drops the lock and schedules.
 */
void unmap_vmas(struct mmu_gather *tlb, struct unmap_desc *unmap)
{
	struct vm_area_struct *vma;
	struct mmu_notifier_range range;
	struct zap_details details = {
		.zap_flags = ZAP_FLAG_DROP_MARKER | ZAP_FLAG_UNMAP,
		/* Careful - we need to zap private pages too! */
		.even_cows = true,
	};

	vma = unmap->first;
	mmu_notifier_range_init(&range, MMU_NOTIFY_UNMAP, 0, vma->vm_mm,
				unmap->vma_start, unmap->vma_end);
	mmu_notifier_invalidate_range_start(&range);
	do {
		unsigned long start = unmap->vma_start;
		unsigned long end = unmap->vma_end;
		hugetlb_zap_begin(vma, &start, &end);
		unmap_single_vma(tlb, vma, start, end, &details);
		hugetlb_zap_end(vma, &details);
		vma = mas_find(unmap->mas, unmap->tree_end - 1);
	} while (vma);
	mmu_notifier_invalidate_range_end(&range);
}

/**
 * zap_page_range_single_batched - remove user pages in a given range
 * @tlb: pointer to the caller's struct mmu_gather
 * @vma: vm_area_struct holding the applicable pages
 * @address: starting address of pages to remove
 * @size: number of bytes to remove
 * @details: details of shared cache invalidation
 *
 * @tlb shouldn't be NULL.  The range must fit into one VMA.  If @vma is for
 * hugetlb, @tlb is flushed and re-initialized by this function.
 */
void zap_page_range_single_batched(struct mmu_gather *tlb,
		struct vm_area_struct *vma, unsigned long address,
		unsigned long size, struct zap_details *details)
{
	const unsigned long end = address + size;
	struct mmu_notifier_range range;

	VM_WARN_ON_ONCE(!tlb || tlb->mm != vma->vm_mm);

	mmu_notifier_range_init(&range, MMU_NOTIFY_CLEAR, 0, vma->vm_mm,
				address, end);
	hugetlb_zap_begin(vma, &range.start, &range.end);
	update_hiwater_rss(vma->vm_mm);
	mmu_notifier_invalidate_range_start(&range);
	/*
	 * unmap 'address-end' not 'range.start-range.end' as range
	 * could have been expanded for hugetlb pmd sharing.
	 */
	unmap_single_vma(tlb, vma, address, end, details);
	mmu_notifier_invalidate_range_end(&range);
	if (is_vm_hugetlb_page(vma)) {
		/*
		 * flush tlb and free resources before hugetlb_zap_end(), to
		 * avoid concurrent page faults' allocation failure.
		 */
		tlb_finish_mmu(tlb);
		hugetlb_zap_end(vma, details);
		tlb_gather_mmu(tlb, vma->vm_mm);
	}
}

/**
 * zap_page_range_single - remove user pages in a given range
 * @vma: vm_area_struct holding the applicable pages
 * @address: starting address of pages to zap
 * @size: number of bytes to zap
 * @details: details of shared cache invalidation
 *
 * The range must fit into one VMA.
 */
void zap_page_range_single(struct vm_area_struct *vma, unsigned long address,
		unsigned long size, struct zap_details *details)
{
	struct mmu_gather tlb;

	tlb_gather_mmu(&tlb, vma->vm_mm);
	zap_page_range_single_batched(&tlb, vma, address, size, details);
	tlb_finish_mmu(&tlb);
}

/**
 * zap_vma_ptes - remove ptes mapping the vma
 * @vma: vm_area_struct holding ptes to be zapped
 * @address: starting address of pages to zap
 * @size: number of bytes to zap
 *
 * This function only unmaps ptes assigned to VM_PFNMAP vmas.
 *
 * The entire address range must be fully contained within the vma.
 *
 */
void zap_vma_ptes(struct vm_area_struct *vma, unsigned long address,
		unsigned long size)
{
	if (!range_in_vma(vma, address, address + size) ||
	    		!(vma->vm_flags & VM_PFNMAP))
		return;

	zap_page_range_single(vma, address, size, NULL);
}
EXPORT_SYMBOL_GPL(zap_vma_ptes);

static pmd_t *walk_to_pmd(struct mm_struct *mm, unsigned long addr)
{
	pgd_t *pgd;
	p4d_t *p4d;
	pud_t *pud;
	pmd_t *pmd;

	pgd = pgd_offset(mm, addr);
	p4d = p4d_alloc(mm, pgd, addr);
	if (!p4d)
		return NULL;
	pud = pud_alloc(mm, p4d, addr);
	if (!pud)
		return NULL;
	pmd = pmd_alloc(mm, pud, addr);
	if (!pmd)
		return NULL;

	VM_BUG_ON(pmd_trans_huge(*pmd));
	return pmd;
}

pte_t *get_locked_pte(struct mm_struct *mm, unsigned long addr,
		      spinlock_t **ptl)
{
	pmd_t *pmd = walk_to_pmd(mm, addr);

	if (!pmd)
		return NULL;
	return pte_alloc_map_lock(mm, pmd, addr, ptl);
}

static bool vm_mixed_zeropage_allowed(struct vm_area_struct *vma)
{
	VM_WARN_ON_ONCE(vma->vm_flags & VM_PFNMAP);
	/*
	 * Whoever wants to forbid the zeropage after some zeropages
	 * might already have been mapped has to scan the page tables and
	 * bail out on any zeropages. Zeropages in COW mappings can
	 * be unshared using FAULT_FLAG_UNSHARE faults.
	 */
	if (mm_forbids_zeropage(vma->vm_mm))
		return false;
	/* zeropages in COW mappings are common and unproblematic. */
	if (is_cow_mapping(vma->vm_flags))
		return true;
	/* Mappings that do not allow for writable PTEs are unproblematic. */
	if (!(vma->vm_flags & (VM_WRITE | VM_MAYWRITE)))
		return true;
	/*
	 * Why not allow any VMA that has vm_ops->pfn_mkwrite? GUP could
	 * find the shared zeropage and longterm-pin it, which would
	 * be problematic as soon as the zeropage gets replaced by a different
	 * page due to vma->vm_ops->pfn_mkwrite, because what's mapped would
	 * now differ to what GUP looked up. FSDAX is incompatible to
	 * FOLL_LONGTERM and VM_IO is incompatible to GUP completely (see
	 * check_vma_flags).
	 */
	return vma->vm_ops && vma->vm_ops->pfn_mkwrite &&
	       (vma_is_fsdax(vma) || vma->vm_flags & VM_IO);
}

static int validate_page_before_insert(struct vm_area_struct *vma,
				       struct page *page)
{
	struct folio *folio = page_folio(page);

	if (!folio_ref_count(folio))
		return -EINVAL;
	if (unlikely(is_zero_folio(folio))) {
		if (!vm_mixed_zeropage_allowed(vma))
			return -EINVAL;
		return 0;
	}
	if (folio_test_anon(folio) || page_has_type(page))
		return -EINVAL;
	flush_dcache_folio(folio);
	return 0;
}

static int insert_page_into_pte_locked(struct vm_area_struct *vma, pte_t *pte,
				unsigned long addr, struct page *page,
				pgprot_t prot, bool mkwrite)
{
	struct folio *folio = page_folio(page);
	pte_t pteval = ptep_get(pte);

	if (!pte_none(pteval)) {
		if (!mkwrite)
			return -EBUSY;

		/* see insert_pfn(). */
		if (pte_pfn(pteval) != page_to_pfn(page)) {
			WARN_ON_ONCE(!is_zero_pfn(pte_pfn(pteval)));
			return -EFAULT;
		}
		pteval = maybe_mkwrite(pteval, vma);
		pteval = pte_mkyoung(pteval);
		if (ptep_set_access_flags(vma, addr, pte, pteval, 1))
			update_mmu_cache(vma, addr, pte);
		return 0;
	}

	/* Ok, finally just insert the thing.. */
	pteval = mk_pte(page, prot);
	if (unlikely(is_zero_folio(folio))) {
		pteval = pte_mkspecial(pteval);
	} else {
		folio_get(folio);
		pteval = mk_pte(page, prot);
		if (mkwrite) {
			pteval = pte_mkyoung(pteval);
			pteval = maybe_mkwrite(pte_mkdirty(pteval), vma);
		}
		inc_mm_counter(vma->vm_mm, mm_counter_file(folio));
		folio_add_file_rmap_pte(folio, page, vma);
	}
	set_pte_at(vma->vm_mm, addr, pte, pteval);
	return 0;
}

static int insert_page(struct vm_area_struct *vma, unsigned long addr,
			struct page *page, pgprot_t prot, bool mkwrite)
{
	int retval;
	pte_t *pte;
	spinlock_t *ptl;

	retval = validate_page_before_insert(vma, page);
	if (retval)
		goto out;
	retval = -ENOMEM;
	pte = get_locked_pte(vma->vm_mm, addr, &ptl);
	if (!pte)
		goto out;
	retval = insert_page_into_pte_locked(vma, pte, addr, page, prot,
					mkwrite);
	pte_unmap_unlock(pte, ptl);
out:
	return retval;
}

static int insert_page_in_batch_locked(struct vm_area_struct *vma, pte_t *pte,
			unsigned long addr, struct page *page, pgprot_t prot)
{
	int err;

	err = validate_page_before_insert(vma, page);
	if (err)
		return err;
	return insert_page_into_pte_locked(vma, pte, addr, page, prot, false);
}

/* insert_pages() amortizes the cost of spinlock operations
 * when inserting pages in a loop.
 */
static int insert_pages(struct vm_area_struct *vma, unsigned long addr,
			struct page **pages, unsigned long *num, pgprot_t prot)
{
	pmd_t *pmd = NULL;
	pte_t *start_pte, *pte;
	spinlock_t *pte_lock;
	struct mm_struct *const mm = vma->vm_mm;
	unsigned long curr_page_idx = 0;
	unsigned long remaining_pages_total = *num;
	unsigned long pages_to_write_in_pmd;
	int ret;
more:
	ret = -EFAULT;
	pmd = walk_to_pmd(mm, addr);
	if (!pmd)
		goto out;

	pages_to_write_in_pmd = min_t(unsigned long,
		remaining_pages_total, PTRS_PER_PTE - pte_index(addr));

	/* Allocate the PTE if necessary; takes PMD lock once only. */
	ret = -ENOMEM;
	if (pte_alloc(mm, pmd))
		goto out;

	while (pages_to_write_in_pmd) {
		int pte_idx = 0;
		const int batch_size = min_t(int, pages_to_write_in_pmd, 8);

		start_pte = pte_offset_map_lock(mm, pmd, addr, &pte_lock);
		if (!start_pte) {
			ret = -EFAULT;
			goto out;
		}
		for (pte = start_pte; pte_idx < batch_size; ++pte, ++pte_idx) {
			int err = insert_page_in_batch_locked(vma, pte,
				addr, pages[curr_page_idx], prot);
			if (unlikely(err)) {
				pte_unmap_unlock(start_pte, pte_lock);
				ret = err;
				remaining_pages_total -= pte_idx;
				goto out;
			}
			addr += PAGE_SIZE;
			++curr_page_idx;
		}
		pte_unmap_unlock(start_pte, pte_lock);
		pages_to_write_in_pmd -= batch_size;
		remaining_pages_total -= batch_size;
	}
	if (remaining_pages_total)
		goto more;
	ret = 0;
out:
	*num = remaining_pages_total;
	return ret;
}

/**
 * vm_insert_pages - insert multiple pages into user vma, batching the pmd lock.
 * @vma: user vma to map to
 * @addr: target start user address of these pages
 * @pages: source kernel pages
 * @num: in: number of pages to map. out: number of pages that were *not*
 * mapped. (0 means all pages were successfully mapped).
 *
 * Preferred over vm_insert_page() when inserting multiple pages.
 *
 * In case of error, we may have mapped a subset of the provided
 * pages. It is the caller's responsibility to account for this case.
 *
 * The same restrictions apply as in vm_insert_page().
 */
int vm_insert_pages(struct vm_area_struct *vma, unsigned long addr,
			struct page **pages, unsigned long *num)
{
	const unsigned long end_addr = addr + (*num * PAGE_SIZE) - 1;

	if (addr < vma->vm_start || end_addr >= vma->vm_end)
		return -EFAULT;
	if (!(vma->vm_flags & VM_MIXEDMAP)) {
		BUG_ON(mmap_read_trylock(vma->vm_mm));
		BUG_ON(vma->vm_flags & VM_PFNMAP);
		vm_flags_set(vma, VM_MIXEDMAP);
	}
	/* Defer page refcount checking till we're about to map that page. */
	return insert_pages(vma, addr, pages, num, vma->vm_page_prot);
}
EXPORT_SYMBOL(vm_insert_pages);

/**
 * vm_insert_page - insert single page into user vma
 * @vma: user vma to map to
 * @addr: target user address of this page
 * @page: source kernel page
 *
 * This allows drivers to insert individual pages they've allocated
 * into a user vma. The zeropage is supported in some VMAs,
 * see vm_mixed_zeropage_allowed().
 *
 * The page has to be a nice clean _individual_ kernel allocation.
 * If you allocate a compound page, you need to have marked it as
 * such (__GFP_COMP), or manually just split the page up yourself
 * (see split_page()).
 *
 * NOTE! Traditionally this was done with "remap_pfn_range()" which
 * took an arbitrary page protection parameter. This doesn't allow
 * that. Your vma protection will have to be set up correctly, which
 * means that if you want a shared writable mapping, you'd better
 * ask for a shared writable mapping!
 *
 * The page does not need to be reserved.
 *
 * Usually this function is called from f_op->mmap() handler
 * under mm->mmap_lock write-lock, so it can change vma->vm_flags.
 * Caller must set VM_MIXEDMAP on vma if it wants to call this
 * function from other places, for example from page-fault handler.
 *
 * Return: %0 on success, negative error code otherwise.
 */
int vm_insert_page(struct vm_area_struct *vma, unsigned long addr,
			struct page *page)
{
	if (addr < vma->vm_start || addr >= vma->vm_end)
		return -EFAULT;
	if (!(vma->vm_flags & VM_MIXEDMAP)) {
		BUG_ON(mmap_read_trylock(vma->vm_mm));
		BUG_ON(vma->vm_flags & VM_PFNMAP);
		vm_flags_set(vma, VM_MIXEDMAP);
	}
	return insert_page(vma, addr, page, vma->vm_page_prot, false);
}
EXPORT_SYMBOL(vm_insert_page);

/*
 * __vm_map_pages - maps range of kernel pages into user vma
 * @vma: user vma to map to
 * @pages: pointer to array of source kernel pages
 * @num: number of pages in page array
 * @offset: user's requested vm_pgoff
 *
 * This allows drivers to map range of kernel pages into a user vma.
 * The zeropage is supported in some VMAs, see
 * vm_mixed_zeropage_allowed().
 *
 * Return: 0 on success and error code otherwise.
 */
static int __vm_map_pages(struct vm_area_struct *vma, struct page **pages,
				unsigned long num, unsigned long offset)
{
	unsigned long count = vma_pages(vma);
	unsigned long uaddr = vma->vm_start;

	/* Fail if the user requested offset is beyond the end of the object */
	if (offset >= num)
		return -ENXIO;

	/* Fail if the user requested size exceeds available object size */
	if (count > num - offset)
		return -ENXIO;

	return vm_insert_pages(vma, uaddr, pages + offset, &count);
}

/**
 * vm_map_pages - maps range of kernel pages starts with non zero offset
 * @vma: user vma to map to
 * @pages: pointer to array of source kernel pages
 * @num: number of pages in page array
 *
 * Maps an object consisting of @num pages, catering for the user's
 * requested vm_pgoff
 *
 * If we fail to insert any page into the vma, the function will return
 * immediately leaving any previously inserted pages present.  Callers
 * from the mmap handler may immediately return the error as their caller
 * will destroy the vma, removing any successfully inserted pages. Other
 * callers should make their own arrangements for calling unmap_region().
 *
 * Context: Process context. Called by mmap handlers.
 * Return: 0 on success and error code otherwise.
 */
int vm_map_pages(struct vm_area_struct *vma, struct page **pages,
				unsigned long num)
{
	return __vm_map_pages(vma, pages, num, vma->vm_pgoff);
}
EXPORT_SYMBOL(vm_map_pages);

/**
 * vm_map_pages_zero - map range of kernel pages starts with zero offset
 * @vma: user vma to map to
 * @pages: pointer to array of source kernel pages
 * @num: number of pages in page array
 *
 * Similar to vm_map_pages(), except that it explicitly sets the offset
 * to 0. This function is intended for the drivers that did not consider
 * vm_pgoff.
 *
 * Context: Process context. Called by mmap handlers.
 * Return: 0 on success and error code otherwise.
 */
int vm_map_pages_zero(struct vm_area_struct *vma, struct page **pages,
				unsigned long num)
{
	return __vm_map_pages(vma, pages, num, 0);
}
EXPORT_SYMBOL(vm_map_pages_zero);

static vm_fault_t insert_pfn(struct vm_area_struct *vma, unsigned long addr,
			unsigned long pfn, pgprot_t prot, bool mkwrite)
{
	struct mm_struct *mm = vma->vm_mm;
	pte_t *pte, entry;
	spinlock_t *ptl;

	pte = get_locked_pte(mm, addr, &ptl);
	if (!pte)
		return VM_FAULT_OOM;
	entry = ptep_get(pte);
	if (!pte_none(entry)) {
		if (mkwrite) {
			/*
			 * For read faults on private mappings the PFN passed
			 * in may not match the PFN we have mapped if the
			 * mapped PFN is a writeable COW page.  In the mkwrite
			 * case we are creating a writable PTE for a shared
			 * mapping and we expect the PFNs to match. If they
			 * don't match, we are likely racing with block
			 * allocation and mapping invalidation so just skip the
			 * update.
			 */
			if (pte_pfn(entry) != pfn) {
				WARN_ON_ONCE(!is_zero_pfn(pte_pfn(entry)));
				goto out_unlock;
			}
			entry = pte_mkyoung(entry);
			entry = maybe_mkwrite(pte_mkdirty(entry), vma);
			if (ptep_set_access_flags(vma, addr, pte, entry, 1))
				update_mmu_cache(vma, addr, pte);
		}
		goto out_unlock;
	}

	/* Ok, finally just insert the thing.. */
	entry = pte_mkspecial(pfn_pte(pfn, prot));

	if (mkwrite) {
		entry = pte_mkyoung(entry);
		entry = maybe_mkwrite(pte_mkdirty(entry), vma);
	}

	set_pte_at(mm, addr, pte, entry);
	update_mmu_cache(vma, addr, pte); /* XXX: why not for insert_page? */

out_unlock:
	pte_unmap_unlock(pte, ptl);
	return VM_FAULT_NOPAGE;
}

/**
 * vmf_insert_pfn_prot - insert single pfn into user vma with specified pgprot
 * @vma: user vma to map to
 * @addr: target user address of this page
 * @pfn: source kernel pfn
 * @pgprot: pgprot flags for the inserted page
 *
 * This is exactly like vmf_insert_pfn(), except that it allows drivers
 * to override pgprot on a per-page basis.
 *
 * This only makes sense for IO mappings, and it makes no sense for
 * COW mappings.  In general, using multiple vmas is preferable;
 * vmf_insert_pfn_prot should only be used if using multiple VMAs is
 * impractical.
 *
 * pgprot typically only differs from @vma->vm_page_prot when drivers set
 * caching- and encryption bits different than those of @vma->vm_page_prot,
 * because the caching- or encryption mode may not be known at mmap() time.
 *
 * This is ok as long as @vma->vm_page_prot is not used by the core vm
 * to set caching and encryption bits for those vmas (except for COW pages).
 * This is ensured by core vm only modifying these page table entries using
 * functions that don't touch caching- or encryption bits, using pte_modify()
 * if needed. (See for example mprotect()).
 *
 * Also when new page-table entries are created, this is only done using the
 * fault() callback, and never using the value of vma->vm_page_prot,
 * except for page-table entries that point to anonymous pages as the result
 * of COW.
 *
 * Context: Process context.  May allocate using %GFP_KERNEL.
 * Return: vm_fault_t value.
 */
vm_fault_t vmf_insert_pfn_prot(struct vm_area_struct *vma, unsigned long addr,
			unsigned long pfn, pgprot_t pgprot)
{
	/*
	 * Technically, architectures with pte_special can avoid all these
	 * restrictions (same for remap_pfn_range).  However we would like
	 * consistency in testing and feature parity among all, so we should
	 * try to keep these invariants in place for everybody.
	 */
	BUG_ON(!(vma->vm_flags & (VM_PFNMAP|VM_MIXEDMAP)));
	BUG_ON((vma->vm_flags & (VM_PFNMAP|VM_MIXEDMAP)) ==
						(VM_PFNMAP|VM_MIXEDMAP));
	BUG_ON((vma->vm_flags & VM_PFNMAP) && is_cow_mapping(vma->vm_flags));
	BUG_ON((vma->vm_flags & VM_MIXEDMAP) && pfn_valid(pfn));

	if (addr < vma->vm_start || addr >= vma->vm_end)
		return VM_FAULT_SIGBUS;

	if (!pfn_modify_allowed(pfn, pgprot))
		return VM_FAULT_SIGBUS;

	pfnmap_setup_cachemode_pfn(pfn, &pgprot);

	return insert_pfn(vma, addr, pfn, pgprot, false);
}
EXPORT_SYMBOL(vmf_insert_pfn_prot);

/**
 * vmf_insert_pfn - insert single pfn into user vma
 * @vma: user vma to map to
 * @addr: target user address of this page
 * @pfn: source kernel pfn
 *
 * Similar to vm_insert_page, this allows drivers to insert individual pages
 * they've allocated into a user vma. Same comments apply.
 *
 * This function should only be called from a vm_ops->fault handler, and
 * in that case the handler should return the result of this function.
 *
 * vma cannot be a COW mapping.
 *
 * As this is called only for pages that do not currently exist, we
 * do not need to flush old virtual caches or the TLB.
 *
 * Context: Process context.  May allocate using %GFP_KERNEL.
 * Return: vm_fault_t value.
 */
vm_fault_t vmf_insert_pfn(struct vm_area_struct *vma, unsigned long addr,
			unsigned long pfn)
{
	return vmf_insert_pfn_prot(vma, addr, pfn, vma->vm_page_prot);
}
EXPORT_SYMBOL(vmf_insert_pfn);

static bool vm_mixed_ok(struct vm_area_struct *vma, unsigned long pfn,
			bool mkwrite)
{
	if (unlikely(is_zero_pfn(pfn)) &&
	    (mkwrite || !vm_mixed_zeropage_allowed(vma)))
		return false;
	/* these checks mirror the abort conditions in vm_normal_page */
	if (vma->vm_flags & VM_MIXEDMAP)
		return true;
	if (is_zero_pfn(pfn))
		return true;
	return false;
}

static vm_fault_t __vm_insert_mixed(struct vm_area_struct *vma,
		unsigned long addr, unsigned long pfn, bool mkwrite)
{
	pgprot_t pgprot = vma->vm_page_prot;
	int err;

	if (!vm_mixed_ok(vma, pfn, mkwrite))
		return VM_FAULT_SIGBUS;

	if (addr < vma->vm_start || addr >= vma->vm_end)
		return VM_FAULT_SIGBUS;

	pfnmap_setup_cachemode_pfn(pfn, &pgprot);

	if (!pfn_modify_allowed(pfn, pgprot))
		return VM_FAULT_SIGBUS;

	/*
	 * If we don't have pte special, then we have to use the pfn_valid()
	 * based VM_MIXEDMAP scheme (see vm_normal_page), and thus we *must*
	 * refcount the page if pfn_valid is true (hence insert_page rather
	 * than insert_pfn).  If a zero_pfn were inserted into a VM_MIXEDMAP
	 * without pte special, it would there be refcounted as a normal page.
	 */
	if (!IS_ENABLED(CONFIG_ARCH_HAS_PTE_SPECIAL) && pfn_valid(pfn)) {
		struct page *page;

		/*
		 * At this point we are committed to insert_page()
		 * regardless of whether the caller specified flags that
		 * result in pfn_t_has_page() == false.
		 */
		page = pfn_to_page(pfn);
		err = insert_page(vma, addr, page, pgprot, mkwrite);
	} else {
		return insert_pfn(vma, addr, pfn, pgprot, mkwrite);
	}

	if (err == -ENOMEM)
		return VM_FAULT_OOM;
	if (err < 0 && err != -EBUSY)
		return VM_FAULT_SIGBUS;

	return VM_FAULT_NOPAGE;
}

vm_fault_t vmf_insert_page_mkwrite(struct vm_fault *vmf, struct page *page,
			bool write)
{
	pgprot_t pgprot = vmf->vma->vm_page_prot;
	unsigned long addr = vmf->address;
	int err;

	if (addr < vmf->vma->vm_start || addr >= vmf->vma->vm_end)
		return VM_FAULT_SIGBUS;

	err = insert_page(vmf->vma, addr, page, pgprot, write);
	if (err == -ENOMEM)
		return VM_FAULT_OOM;
	if (err < 0 && err != -EBUSY)
		return VM_FAULT_SIGBUS;

	return VM_FAULT_NOPAGE;
}
EXPORT_SYMBOL_GPL(vmf_insert_page_mkwrite);

vm_fault_t vmf_insert_mixed(struct vm_area_struct *vma, unsigned long addr,
		unsigned long pfn)
{
	return __vm_insert_mixed(vma, addr, pfn, false);
}
EXPORT_SYMBOL(vmf_insert_mixed);

/*
 *  If the insertion of PTE failed because someone else already added a
 *  different entry in the mean time, we treat that as success as we assume
 *  the same entry was actually inserted.
 */
vm_fault_t vmf_insert_mixed_mkwrite(struct vm_area_struct *vma,
		unsigned long addr, unsigned long pfn)
{
	return __vm_insert_mixed(vma, addr, pfn, true);
}

/*
 * maps a range of physical memory into the requested pages. the old
 * mappings are removed. any references to nonexistent pages results
 * in null mappings (currently treated as "copy-on-access")
 */
static int remap_pte_range(struct mm_struct *mm, pmd_t *pmd,
			unsigned long addr, unsigned long end,
			unsigned long pfn, pgprot_t prot)
{
	pte_t *pte, *mapped_pte;
	spinlock_t *ptl;
	int err = 0;

	mapped_pte = pte = pte_alloc_map_lock(mm, pmd, addr, &ptl);
	if (!pte)
		return -ENOMEM;
	lazy_mmu_mode_enable();
	do {
		BUG_ON(!pte_none(ptep_get(pte)));
		if (!pfn_modify_allowed(pfn, prot)) {
			err = -EACCES;
			break;
		}
		set_pte_at(mm, addr, pte, pte_mkspecial(pfn_pte(pfn, prot)));
		pfn++;
	} while (pte++, addr += PAGE_SIZE, addr != end);
	lazy_mmu_mode_disable();
	pte_unmap_unlock(mapped_pte, ptl);
	return err;
}

static inline int remap_pmd_range(struct mm_struct *mm, pud_t *pud,
			unsigned long addr, unsigned long end,
			unsigned long pfn, pgprot_t prot)
{
	pmd_t *pmd;
	unsigned long next;
	int err;

	pfn -= addr >> PAGE_SHIFT;
	pmd = pmd_alloc(mm, pud, addr);
	if (!pmd)
		return -ENOMEM;
	VM_BUG_ON(pmd_trans_huge(*pmd));
	do {
		next = pmd_addr_end(addr, end);
		err = remap_pte_range(mm, pmd, addr, next,
				pfn + (addr >> PAGE_SHIFT), prot);
		if (err)
			return err;
	} while (pmd++, addr = next, addr != end);
	return 0;
}

static inline int remap_pud_range(struct mm_struct *mm, p4d_t *p4d,
			unsigned long addr, unsigned long end,
			unsigned long pfn, pgprot_t prot)
{
	pud_t *pud;
	unsigned long next;
	int err;

	pfn -= addr >> PAGE_SHIFT;
	pud = pud_alloc(mm, p4d, addr);
	if (!pud)
		return -ENOMEM;
	do {
		next = pud_addr_end(addr, end);
		err = remap_pmd_range(mm, pud, addr, next,
				pfn + (addr >> PAGE_SHIFT), prot);
		if (err)
			return err;
	} while (pud++, addr = next, addr != end);
	return 0;
}

static inline int remap_p4d_range(struct mm_struct *mm, pgd_t *pgd,
			unsigned long addr, unsigned long end,
			unsigned long pfn, pgprot_t prot)
{
	p4d_t *p4d;
	unsigned long next;
	int err;

	pfn -= addr >> PAGE_SHIFT;
	p4d = p4d_alloc(mm, pgd, addr);
	if (!p4d)
		return -ENOMEM;
	do {
		next = p4d_addr_end(addr, end);
		err = remap_pud_range(mm, p4d, addr, next,
				pfn + (addr >> PAGE_SHIFT), prot);
		if (err)
			return err;
	} while (p4d++, addr = next, addr != end);
	return 0;
}

static int get_remap_pgoff(bool is_cow, unsigned long addr,
		unsigned long end, unsigned long vm_start, unsigned long vm_end,
		unsigned long pfn, pgoff_t *vm_pgoff_p)
{
	/*
	 * There's a horrible special case to handle copy-on-write
	 * behaviour that some programs depend on. We mark the "original"
	 * un-COW'ed pages by matching them up with "vma->vm_pgoff".
	 * See vm_normal_page() for details.
	 */
	if (is_cow) {
		if (addr != vm_start || end != vm_end)
			return -EINVAL;
		*vm_pgoff_p = pfn;
	}

	return 0;
}

static int remap_pfn_range_internal(struct vm_area_struct *vma, unsigned long addr,
		unsigned long pfn, unsigned long size, pgprot_t prot)
{
	pgd_t *pgd;
	unsigned long next;
	unsigned long end = addr + PAGE_ALIGN(size);
	struct mm_struct *mm = vma->vm_mm;
	int err;

	if (WARN_ON_ONCE(!PAGE_ALIGNED(addr)))
		return -EINVAL;

	VM_WARN_ON_ONCE(!vma_test_all_flags_mask(vma, VMA_REMAP_FLAGS));

	BUG_ON(addr >= end);
	pfn -= addr >> PAGE_SHIFT;
	pgd = pgd_offset(mm, addr);
	flush_cache_range(vma, addr, end);
	do {
		next = pgd_addr_end(addr, end);
		err = remap_p4d_range(mm, pgd, addr, next,
				pfn + (addr >> PAGE_SHIFT), prot);
		if (err)
			return err;
	} while (pgd++, addr = next, addr != end);

	return 0;
}

/*
 * Variant of remap_pfn_range that does not call track_pfn_remap.  The caller
 * must have pre-validated the caching bits of the pgprot_t.
 */
static int remap_pfn_range_notrack(struct vm_area_struct *vma, unsigned long addr,
		unsigned long pfn, unsigned long size, pgprot_t prot)
{
	int error = remap_pfn_range_internal(vma, addr, pfn, size, prot);

	if (!error)
		return 0;

	/*
	 * A partial pfn range mapping is dangerous: it does not
	 * maintain page reference counts, and callers may free
	 * pages due to the error. So zap it early.
	 */
	zap_page_range_single(vma, addr, size, NULL);
	return error;
}

#ifdef __HAVE_PFNMAP_TRACKING
static inline struct pfnmap_track_ctx *pfnmap_track_ctx_alloc(unsigned long pfn,
		unsigned long size, pgprot_t *prot)
{
	struct pfnmap_track_ctx *ctx;

	if (pfnmap_track(pfn, size, prot))
		return ERR_PTR(-EINVAL);

	ctx = kmalloc_obj(*ctx);
	if (unlikely(!ctx)) {
		pfnmap_untrack(pfn, size);
		return ERR_PTR(-ENOMEM);
	}

	ctx->pfn = pfn;
	ctx->size = size;
	kref_init(&ctx->kref);
	return ctx;
}

void pfnmap_track_ctx_release(struct kref *ref)
{
	struct pfnmap_track_ctx *ctx = container_of(ref, struct pfnmap_track_ctx, kref);

	pfnmap_untrack(ctx->pfn, ctx->size);
	kfree(ctx);
}

static int remap_pfn_range_track(struct vm_area_struct *vma, unsigned long addr,
		unsigned long pfn, unsigned long size, pgprot_t prot)
{
	struct pfnmap_track_ctx *ctx = NULL;
	int err;

	size = PAGE_ALIGN(size);

	/*
	 * If we cover the full VMA, we'll perform actual tracking, and
	 * remember to untrack when the last reference to our tracking
	 * context from a VMA goes away. We'll keep tracking the whole pfn
	 * range even during VMA splits and partial unmapping.
	 *
	 * If we only cover parts of the VMA, we'll only setup the cachemode
	 * in the pgprot for the pfn range.
	 */
	if (addr == vma->vm_start && addr + size == vma->vm_end) {
		if (vma->pfnmap_track_ctx)
			return -EINVAL;
		ctx = pfnmap_track_ctx_alloc(pfn, size, &prot);
		if (IS_ERR(ctx))
			return PTR_ERR(ctx);
	} else if (pfnmap_setup_cachemode(pfn, size, &prot)) {
		return -EINVAL;
	}

	err = remap_pfn_range_notrack(vma, addr, pfn, size, prot);
	if (ctx) {
		if (err)
			kref_put(&ctx->kref, pfnmap_track_ctx_release);
		else
			vma->pfnmap_track_ctx = ctx;
	}
	return err;
}

static int do_remap_pfn_range(struct vm_area_struct *vma, unsigned long addr,
		unsigned long pfn, unsigned long size, pgprot_t prot)
{
	return remap_pfn_range_track(vma, addr, pfn, size, prot);
}
#else
static int do_remap_pfn_range(struct vm_area_struct *vma, unsigned long addr,
		unsigned long pfn, unsigned long size, pgprot_t prot)
{
	return remap_pfn_range_notrack(vma, addr, pfn, size, prot);
}
#endif

void remap_pfn_range_prepare(struct vm_area_desc *desc, unsigned long pfn)
{
	/*
	 * We set addr=VMA start, end=VMA end here, so this won't fail, but we
	 * check it again on complete and will fail there if specified addr is
	 * invalid.
	 */
	get_remap_pgoff(vma_desc_is_cow_mapping(desc), desc->start, desc->end,
			desc->start, desc->end, pfn, &desc->pgoff);
	vma_desc_set_flags_mask(desc, VMA_REMAP_FLAGS);
}

static int remap_pfn_range_prepare_vma(struct vm_area_struct *vma, unsigned long addr,
		unsigned long pfn, unsigned long size)
{
	unsigned long end = addr + PAGE_ALIGN(size);
	int err;

	err = get_remap_pgoff(is_cow_mapping(vma->vm_flags), addr, end,
			      vma->vm_start, vma->vm_end, pfn, &vma->vm_pgoff);
	if (err)
		return err;

	vma_set_flags_mask(vma, VMA_REMAP_FLAGS);
	return 0;
}

/**
 * remap_pfn_range - remap kernel memory to userspace
 * @vma: user vma to map to
 * @addr: target page aligned user address to start at
 * @pfn: page frame number of kernel physical memory address
 * @size: size of mapping area
 * @prot: page protection flags for this mapping
 *
 * Note: this is only safe if the mm semaphore is held when called.
 *
 * Return: %0 on success, negative error code otherwise.
 */
int remap_pfn_range(struct vm_area_struct *vma, unsigned long addr,
		    unsigned long pfn, unsigned long size, pgprot_t prot)
{
	int err;

	err = remap_pfn_range_prepare_vma(vma, addr, pfn, size);
	if (err)
		return err;

	return do_remap_pfn_range(vma, addr, pfn, size, prot);
}
EXPORT_SYMBOL(remap_pfn_range);

int remap_pfn_range_complete(struct vm_area_struct *vma, unsigned long addr,
		unsigned long pfn, unsigned long size, pgprot_t prot)
{
	return do_remap_pfn_range(vma, addr, pfn, size, prot);
}

/**
 * vm_iomap_memory - remap memory to userspace
 * @vma: user vma to map to
 * @start: start of the physical memory to be mapped
 * @len: size of area
 *
 * This is a simplified io_remap_pfn_range() for common driver use. The
 * driver just needs to give us the physical memory range to be mapped,
 * we'll figure out the rest from the vma information.
 *
 * NOTE! Some drivers might want to tweak vma->vm_page_prot first to get
 * whatever write-combining details or similar.
 *
 * Return: %0 on success, negative error code otherwise.
 */
int vm_iomap_memory(struct vm_area_struct *vma, phys_addr_t start, unsigned long len)
{
	unsigned long vm_len, pfn, pages;

	/* Check that the physical memory area passed in looks valid */
	if (start + len < start)
		return -EINVAL;
	/*
	 * You *really* shouldn't map things that aren't page-aligned,
	 * but we've historically allowed it because IO memory might
	 * just have smaller alignment.
	 */
	len += start & ~PAGE_MASK;
	pfn = start >> PAGE_SHIFT;
	pages = (len + ~PAGE_MASK) >> PAGE_SHIFT;
	if (pfn + pages < pfn)
		return -EINVAL;

	/* We start the mapping 'vm_pgoff' pages into the area */
	if (vma->vm_pgoff > pages)
		return -EINVAL;
	pfn += vma->vm_pgoff;
	pages -= vma->vm_pgoff;

	/* Can we fit all of the mapping? */
	vm_len = vma->vm_end - vma->vm_start;
	if (vm_len >> PAGE_SHIFT > pages)
		return -EINVAL;

	/* Ok, let it rip */
	return io_remap_pfn_range(vma, vma->vm_start, pfn, vm_len, vma->vm_page_prot);
}
EXPORT_SYMBOL(vm_iomap_memory);

static int apply_to_pte_range(struct mm_struct *mm, pmd_t *pmd,
				     unsigned long addr, unsigned long end,
				     pte_fn_t fn, void *data, bool create,
				     pgtbl_mod_mask *mask)
{
	pte_t *pte, *mapped_pte;
	int err = 0;
	spinlock_t *ptl;

	if (create) {
		mapped_pte = pte = (mm == &init_mm) ?
			pte_alloc_kernel_track(pmd, addr, mask) :
			pte_alloc_map_lock(mm, pmd, addr, &ptl);
		if (!pte)
			return -ENOMEM;
	} else {
		mapped_pte = pte = (mm == &init_mm) ?
			pte_offset_kernel(pmd, addr) :
			pte_offset_map_lock(mm, pmd, addr, &ptl);
		if (!pte)
			return -EINVAL;
	}

	lazy_mmu_mode_enable();

	if (fn) {
		do {
			if (create || !pte_none(ptep_get(pte))) {
				err = fn(pte, addr, data);
				if (err)
					break;
			}
		} while (pte++, addr += PAGE_SIZE, addr != end);
	}
	*mask |= PGTBL_PTE_MODIFIED;

	lazy_mmu_mode_disable();

	if (mm != &init_mm)
		pte_unmap_unlock(mapped_pte, ptl);
	return err;
}

static int apply_to_pmd_range(struct mm_struct *mm, pud_t *pud,
				     unsigned long addr, unsigned long end,
				     pte_fn_t fn, void *data, bool create,
				     pgtbl_mod_mask *mask)
{
	pmd_t *pmd;
	unsigned long next;
	int err = 0;

	BUG_ON(pud_leaf(*pud));

	if (create) {
		pmd = pmd_alloc_track(mm, pud, addr, mask);
		if (!pmd)
			return -ENOMEM;
	} else {
		pmd = pmd_offset(pud, addr);
	}
	do {
		next = pmd_addr_end(addr, end);
		if (pmd_none(*pmd) && !create)
			continue;
		if (WARN_ON_ONCE(pmd_leaf(*pmd)))
			return -EINVAL;
		if (!pmd_none(*pmd) && WARN_ON_ONCE(pmd_bad(*pmd))) {
			if (!create)
				continue;
			pmd_clear_bad(pmd);
		}
		err = apply_to_pte_range(mm, pmd, addr, next,
					 fn, data, create, mask);
		if (err)
			break;
	} while (pmd++, addr = next, addr != end);

	return err;
}

static int apply_to_pud_range(struct mm_struct *mm, p4d_t *p4d,
				     unsigned long addr, unsigned long end,
				     pte_fn_t fn, void *data, bool create,
				     pgtbl_mod_mask *mask)
{
	pud_t *pud;
	unsigned long next;
	int err = 0;

	if (create) {
		pud = pud_alloc_track(mm, p4d, addr, mask);
		if (!pud)
			return -ENOMEM;
	} else {
		pud = pud_offset(p4d, addr);
	}
	do {
		next = pud_addr_end(addr, end);
		if (pud_none(*pud) && !create)
			continue;
		if (WARN_ON_ONCE(pud_leaf(*pud)))
			return -EINVAL;
		if (!pud_none(*pud) && WARN_ON_ONCE(pud_bad(*pud))) {
			if (!create)
				continue;
			pud_clear_bad(pud);
		}
		err = apply_to_pmd_range(mm, pud, addr, next,
					 fn, data, create, mask);
		if (err)
			break;
	} while (pud++, addr = next, addr != end);

	return err;
}

static int apply_to_p4d_range(struct mm_struct *mm, pgd_t *pgd,
				     unsigned long addr, unsigned long end,
				     pte_fn_t fn, void *data, bool create,
				     pgtbl_mod_mask *mask)
{
	p4d_t *p4d;
	unsigned long next;
	int err = 0;

	if (create) {
		p4d = p4d_alloc_track(mm, pgd, addr, mask);
		if (!p4d)
			return -ENOMEM;
	} else {
		p4d = p4d_offset(pgd, addr);
	}
	do {
		next = p4d_addr_end(addr, end);
		if (p4d_none(*p4d) && !create)
			continue;
		if (WARN_ON_ONCE(p4d_leaf(*p4d)))
			return -EINVAL;
		if (!p4d_none(*p4d) && WARN_ON_ONCE(p4d_bad(*p4d))) {
			if (!create)
				continue;
			p4d_clear_bad(p4d);
		}
		err = apply_to_pud_range(mm, p4d, addr, next,
					 fn, data, create, mask);
		if (err)
			break;
	} while (p4d++, addr = next, addr != end);

	return err;
}

static int __apply_to_page_range(struct mm_struct *mm, unsigned long addr,
				 unsigned long size, pte_fn_t fn,
				 void *data, bool create)
{
	pgd_t *pgd;
	unsigned long start = addr, next;
	unsigned long end = addr + size;
	pgtbl_mod_mask mask = 0;
	int err = 0;

	if (WARN_ON(addr >= end))
		return -EINVAL;

	pgd = pgd_offset(mm, addr);
	do {
		next = pgd_addr_end(addr, end);
		if (pgd_none(*pgd) && !create)
			continue;
		if (WARN_ON_ONCE(pgd_leaf(*pgd))) {
			err = -EINVAL;
			break;
		}
		if (!pgd_none(*pgd) && WARN_ON_ONCE(pgd_bad(*pgd))) {
			if (!create)
				continue;
			pgd_clear_bad(pgd);
		}
		err = apply_to_p4d_range(mm, pgd, addr, next,
					 fn, data, create, &mask);
		if (err)
			break;
	} while (pgd++, addr = next, addr != end);

	if (mask & ARCH_PAGE_TABLE_SYNC_MASK)
		arch_sync_kernel_mappings(start, start + size);

	return err;
}

/*
 * Scan a region of virtual memory, filling in page tables as necessary
 * and calling a provided function on each leaf page table.
 */
int apply_to_page_range(struct mm_struct *mm, unsigned long addr,
			unsigned long size, pte_fn_t fn, void *data)
{
	return __apply_to_page_range(mm, addr, size, fn, data, true);
}
EXPORT_SYMBOL_GPL(apply_to_page_range);

/*
 * Scan a region of virtual memory, calling a provided function on
 * each leaf page table where it exists.
 *
 * Unlike apply_to_page_range, this does _not_ fill in page tables
 * where they are absent.
 */
int apply_to_existing_page_range(struct mm_struct *mm, unsigned long addr,
				 unsigned long size, pte_fn_t fn, void *data)
{
	return __apply_to_page_range(mm, addr, size, fn, data, false);
}

/*
 * handle_pte_fault chooses page fault handler according to an entry which was
 * read non-atomically.  Before making any commitment, on those architectures
 * or configurations (e.g. i386 with PAE) which might give a mix of unmatched
 * parts, do_swap_page must check under lock before unmapping the pte and
 * proceeding (but do_wp_page is only called after already making such a check;
 * and do_anonymous_page can safely check later on).
 */
static inline int pte_unmap_same(struct vm_fault *vmf)
{
	int same = 1;
#if defined(CONFIG_SMP) || defined(CONFIG_PREEMPTION)
	if (sizeof(pte_t) > sizeof(unsigned long)) {
		spin_lock(vmf->ptl);
		same = pte_same(ptep_get(vmf->pte), vmf->orig_pte);
		spin_unlock(vmf->ptl);
	}
#endif
	pte_unmap(vmf->pte);
	vmf->pte = NULL;
	return same;
}

/*
 * Return:
 *	0:		copied succeeded
 *	-EHWPOISON:	copy failed due to hwpoison in source page
 *	-EAGAIN:	copied failed (some other reason)
 */
static inline int __wp_page_copy_user(struct page *dst, struct page *src,
				      struct vm_fault *vmf)
{
	int ret;
	void *kaddr;
	void __user *uaddr;
	struct vm_area_struct *vma = vmf->vma;
	struct mm_struct *mm = vma->vm_mm;
	unsigned long addr = vmf->address;

	if (likely(src)) {
		if (copy_mc_user_highpage(dst, src, addr, vma))
			return -EHWPOISON;
		return 0;
	}

	/*
	 * If the source page was a PFN mapping, we don't have
	 * a "struct page" for it. We do a best-effort copy by
	 * just copying from the original user address. If that
	 * fails, we just zero-fill it. Live with it.
	 */
	kaddr = kmap_local_page(dst);
	pagefault_disable();
	uaddr = (void __user *)(addr & PAGE_MASK);

	/*
	 * On arch
