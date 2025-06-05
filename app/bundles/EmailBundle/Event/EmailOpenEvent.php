<?php

namespace Mautic\EmailBundle\Event;

use Mautic\CoreBundle\Event\CommonEvent;
use Mautic\EmailBundle\Entity\Email;
use Mautic\EmailBundle\Entity\Stat;
use Symfony\Component\HttpFoundation\Request;

class EmailOpenEvent extends CommonEvent
{
    private ?Email $email;
    private bool $doNotRecordHit = false;

    public function __construct(
        Stat                     $stat,
        private readonly Request $request,
        private readonly bool    $firstTime = false
    ) {
        $this->entity    = $stat;
        $this->email     = $stat->getEmail();
    }

    /**
     * Returns the Email entity.
     *
     * @return Email
     */
    public function getEmail()
    {
        return $this->email;
    }

    /**
     * Get email request.
     *
     * @return string
     */
    public function getRequest()
    {
        return $this->request;
    }

    /**
     * @return Stat
     */
    public function getStat()
    {
        return $this->entity;
    }

    /**
     * Returns if this is first time the email is read.
     *
     * @return bool
     */
    public function isFirstTime()
    {
        return $this->firstTime;
    }

    public function isDoNotRecordHit(): bool
    {
        return $this->doNotRecordHit;
    }

    public function setDoNotRecordHit(bool $doNotRecordHit = true): void
    {
        $this->doNotRecordHit = $doNotRecordHit;
    }

}
